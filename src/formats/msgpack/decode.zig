// serval-bfi
//! Schema-driven MessagePack decode. The wire format is implemented
//! in-tree (no std support); typed construction is driven by Schema(T)
//! exactly like serval-json: wire names, presence tracking, unknown-field
//! policy, validation integration. Ext types are not supported.
//!
//! Memory: strings/bytes reference the input buffer unless
//! MemoryMode.owned duplicates them. Pass an arena and free wholesale.

const std = @import("std");
const core = @import("serval-core");
const codec = @import("serval-codec");
const validate = @import("serval-validate");

pub const Error = core.DecodeError || error{ValidationFailed};

/// Typed fast path; see decodeResult for the report-carrying pipeline.
pub fn decode(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) Error!T {
    const result = try decodeResult(T, allocator, input, options);
    return unwrapResult(T, allocator, result);
}

/// Borrowed decode: result slices point into `input` — valid only while it
/// is. Zero allocations for flat structs with `.validation = .none`.
pub fn decodeBorrowed(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) Error!codec.borrow.Borrowed(T) {
    var opts = options;
    opts.memory = .borrowed;
    return .{ .value = try decode(T, allocator, input, opts) };
}

/// Streaming decode: slurps the reader, then runs the normal pipeline.
/// Forces MemoryMode.owned — the slurped buffer is freed before returning,
/// so borrowed results would dangle.
pub fn decodeFromReader(
    comptime T: type,
    allocator: std.mem.Allocator,
    io_reader: *std.Io.Reader,
    options: codec.DecodeOptions,
) Error!T {
    const input = io_reader.allocRemaining(allocator, .unlimited) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReadFailed => return error.ReadFailed,
        error.StreamTooLong => unreachable, // .unlimited
    };
    defer allocator.free(input);
    var opts = options;
    opts.memory = .owned;
    return decode(T, allocator, input, opts);
}

// serval-l3p
/// Public dynamic decode: the whole document as a format-neutral
/// core.Value tree. Memory rules match decode(); pass an arena.
pub fn decodeValueSlice(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) core.DecodeError!core.Value {
    var ctx = core.ValidateContext.init(allocator);
    defer ctx.deinit();

    var d = Decoder{
        .buf = input,
        .allocator = allocator,
        .options = options,
        .ctx = &ctx,
        .present = .empty,
    };
    defer d.present.deinit(allocator);
    defer d.unknown.deinit(allocator);

    const v = try decodeValue(&d);
    if (d.pos != d.buf.len) return error.UnexpectedToken;
    return v;
}

pub fn decodeResult(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) error{OutOfMemory}!core.DecodeResult(T) {
    var ctx = core.ValidateContext.init(allocator);
    defer ctx.deinit();

    var d = Decoder{
        .buf = input,
        .allocator = allocator,
        .options = options,
        .ctx = &ctx,
        .present = .empty,
    };
    defer d.present.deinit(allocator);
    defer d.unknown.deinit(allocator);

    const value = decodeTop(T, &d) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .decode_error = e },
    };
    if (d.pos != d.buf.len) return .{ .decode_error = error.UnexpectedToken };

    // Shape issues: the value may contain undefined fields.
    if (ctx.issues.items.len > 0) {
        const issues = ctx.issues.toOwnedSlice(ctx.allocator) catch return error.OutOfMemory;
        return .{ .invalid = .{ .issues = issues } };
    }

    const unknown = d.unknown.toOwnedSlice(allocator) catch return error.OutOfMemory;

    if (options.validation != .none) {
        const report = validate.check(T, &value, allocator, .{
            .present_fields = d.present.items,
        }) catch return error.OutOfMemory;
        if (!report.ok()) {
            if (options.validation == .lax) {
                return .{ .ok = .{ .value = value, .warnings = report, .unknown = unknown } };
            }
            allocator.free(unknown);
            return .{ .invalid = report };
        }
        allocator.free(report.issues);
    }

    return .{ .ok = .{ .value = value, .unknown = unknown } };
}

fn unwrapResult(
    comptime T: type,
    allocator: std.mem.Allocator,
    result: core.DecodeResult(T),
) Error!T {
    switch (result) {
        .ok => |ok| {
            allocator.free(ok.warnings.issues);
            allocator.free(ok.unknown);
            return ok.value;
        },
        .invalid => |report| {
            defer allocator.free(report.issues);
            for (report.issues) |i| {
                if (i.code == .unknown_field) return error.UnknownField;
            }
            for (report.issues) |i| {
                if (i.code == .required) return error.MissingRequiredField;
            }
            return error.ValidationFailed;
        },
        .decode_error => |e| return e,
    }
}

// serval-1f7: containers recurse — a 1-byte fixarray header per level
// would otherwise turn input length into stack depth.
const max_nesting = 256;

const Decoder = struct {
    buf: []const u8,
    pos: usize = 0,
    allocator: std.mem.Allocator,
    options: codec.DecodeOptions,
    ctx: *core.ValidateContext,
    /// Zig field names seen at the top level (comptime strings; no copies).
    present: std.ArrayList([]const u8),
    /// Top-level unknown fields gathered under .collect.
    unknown: std.ArrayList(core.FieldValue) = .empty,
    // serval-1f7
    depth: usize = 0,

    fn enterNest(d: *Decoder) core.DecodeError!void {
        d.depth += 1;
        if (d.depth > max_nesting) return error.InvalidSyntax;
    }

    fn readByte(d: *Decoder) core.DecodeError!u8 {
        if (d.pos >= d.buf.len) return error.UnexpectedEndOfInput;
        defer d.pos += 1;
        return d.buf[d.pos];
    }

    fn readSlice(d: *Decoder, n: usize) core.DecodeError![]const u8 {
        if (d.buf.len - d.pos < n) return error.UnexpectedEndOfInput;
        defer d.pos += n;
        return d.buf[d.pos .. d.pos + n];
    }

    fn readBig(d: *Decoder, comptime U: type) core.DecodeError!U {
        const bytes = try d.readSlice(@divExact(@bitSizeOf(U), 8));
        return std.mem.readInt(U, bytes[0..@divExact(@bitSizeOf(U), 8)], .big);
    }
};

fn decodeTop(comptime T: type, d: *Decoder) core.DecodeError!T {
    if (@typeInfo(T) == .@"struct") return decodeStruct(T, d, true);
    return decodeAny(T, d, .{});
}

// Header classification for one msgpack value.
const Header = union(enum) {
    int: i128,
    float: f64,
    bool: bool,
    nil,
    str: usize,
    bin: usize,
    array: usize,
    map: usize,
};

fn readHeader(d: *Decoder) core.DecodeError!Header {
    const b = try d.readByte();
    return switch (b) {
        0x00...0x7f => .{ .int = b },
        0xe0...0xff => .{ .int = @as(i8, @bitCast(b)) },
        0xcc => .{ .int = try d.readBig(u8) },
        0xcd => .{ .int = try d.readBig(u16) },
        0xce => .{ .int = try d.readBig(u32) },
        0xcf => .{ .int = try d.readBig(u64) },
        0xd0 => .{ .int = @as(i8, @bitCast(try d.readBig(u8))) },
        0xd1 => .{ .int = @as(i16, @bitCast(try d.readBig(u16))) },
        0xd2 => .{ .int = @as(i32, @bitCast(try d.readBig(u32))) },
        0xd3 => .{ .int = @as(i64, @bitCast(try d.readBig(u64))) },
        0xca => .{ .float = @as(f32, @bitCast(try d.readBig(u32))) },
        0xcb => .{ .float = @as(f64, @bitCast(try d.readBig(u64))) },
        0xc2 => .{ .bool = false },
        0xc3 => .{ .bool = true },
        0xc0 => .nil,
        0xa0...0xbf => .{ .str = b & 0x1f },
        0xd9 => .{ .str = try d.readBig(u8) },
        0xda => .{ .str = try d.readBig(u16) },
        0xdb => .{ .str = try d.readBig(u32) },
        0xc4 => .{ .bin = try d.readBig(u8) },
        0xc5 => .{ .bin = try d.readBig(u16) },
        0xc6 => .{ .bin = try d.readBig(u32) },
        0x90...0x9f => .{ .array = b & 0x0f },
        0xdc => .{ .array = try d.readBig(u16) },
        0xdd => .{ .array = try d.readBig(u32) },
        0x80...0x8f => .{ .map = b & 0x0f },
        0xde => .{ .map = try d.readBig(u16) },
        0xdf => .{ .map = try d.readBig(u32) },
        // ext family (0xc1 is never used; 0xc7-0xc9, 0xd4-0xd8 are ext)
        else => error.UnexpectedToken,
    };
}

fn skipValue(d: *Decoder) core.DecodeError!void {
    switch (try readHeader(d)) {
        .int, .float, .bool, .nil => {},
        .str, .bin => |n| _ = try d.readSlice(n),
        .array => |n| {
            try d.enterNest();
            defer d.depth -= 1;
            for (0..n) |_| try skipValue(d);
        },
        .map => |n| {
            try d.enterNest();
            defer d.depth -= 1;
            for (0..n) |_| {
                try skipValue(d);
                try skipValue(d);
            }
        },
    }
}

fn readStr(d: *Decoder, dupe_for_owned: bool) core.DecodeError![]const u8 {
    const n = switch (try readHeader(d)) {
        .str, .bin => |n| n,
        else => return error.UnexpectedToken,
    };
    const s = try d.readSlice(n);
    if (dupe_for_owned and d.options.memory == .owned) {
        return d.allocator.dupe(u8, s) catch error.OutOfMemory;
    }
    return s;
}

fn decodeAny(
    comptime T: type,
    d: *Decoder,
    comptime parent: core.TypeOptions,
) core.DecodeError!T {
    switch (@typeInfo(T)) {
        .bool => return switch (try readHeader(d)) {
            .bool => |b| b,
            else => error.UnexpectedToken,
        },
        .int => return switch (try readHeader(d)) {
            .int => |n| std.math.cast(T, n) orelse error.Overflow,
            else => error.UnexpectedToken,
        },
        .float => return switch (try readHeader(d)) {
            .float => |f| @floatCast(f),
            .int => |n| @floatFromInt(n),
            else => error.UnexpectedToken,
        },
        .optional => |o| {
            if (d.pos < d.buf.len and d.buf[d.pos] == 0xc0) {
                d.pos += 1;
                return null;
            }
            return try decodeAny(o.child, d, parent);
        },
        .@"enum" => switch (parent.enum_tagging) {
            .name => {
                const s = try readStr(d, false);
                return std.meta.stringToEnum(T, s) orelse error.InvalidEnumTag;
            },
            .value => return switch (try readHeader(d)) {
                .int => |n| std.enums.fromInt(T, n) orelse error.InvalidEnumTag,
                else => error.UnexpectedToken,
            },
        },
        .pointer => |p| {
            if (p.size != .slice)
                @compileError("serval-msgpack: unsupported pointer type " ++ @typeName(T));
            // str/bin accepted interchangeably for []u8 regardless of policy.
            if (p.child == u8) return try readStr(d, true);
            return try decodeSlice(p.child, d, parent);
        },
        .@"struct" => return decodeStruct(T, d, false),
        .@"union" => return decodeUnion(T, d),
        else => @compileError("serval-msgpack: unsupported type " ++ @typeName(T)),
    }
}

fn decodeSlice(
    comptime Child: type,
    d: *Decoder,
    comptime parent: core.TypeOptions,
) core.DecodeError![]const Child {
    const n = switch (try readHeader(d)) {
        .array => |n| n,
        else => return error.UnexpectedToken,
    };
    try d.enterNest();
    defer d.depth -= 1;
    const out = d.allocator.alloc(Child, n) catch return error.OutOfMemory;
    for (out) |*slot| slot.* = try decodeAny(Child, d, parent);
    return out;
}

fn decodeStruct(comptime T: type, d: *Decoder, comptime is_top: bool) core.DecodeError!T {
    const n = switch (try readHeader(d)) {
        .map => |n| n,
        else => return error.UnexpectedToken,
    };
    try d.enterNest();
    defer d.depth -= 1;
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;
    var seen = [_]bool{false} ** struct_fields.len;

    key_loop: for (0..n) |_| {
        const key = blk: {
            const kn = switch (try readHeader(d)) {
                .str => |kn| kn,
                else => return error.UnexpectedToken,
            };
            break :blk try d.readSlice(kn);
        };
        inline for (S.fields, struct_fields, 0..) |sf, zf, i| {
            if (std.mem.eql(u8, key, sf.wire_name)) {
                @field(result, zf.name) = try decodeAny(zf.type, d, S.options);
                seen[i] = true;
                if (is_top and d.options.validation != .none) {
                    d.present.append(d.allocator, zf.name) catch return error.OutOfMemory;
                }
                continue :key_loop;
            }
        }
        switch (d.options.unknown_fields) {
            .reject => {
                d.ctx.issue(.{
                    .path = .root,
                    .code = .unknown_field,
                    .message = "unknown field in input",
                });
                try skipValue(d);
            },
            .collect => if (is_top) {
                const owned_key = if (d.options.memory == .owned)
                    d.allocator.dupe(u8, key) catch return error.OutOfMemory
                else
                    key;
                const val = try decodeValue(d);
                d.unknown.append(d.allocator, .{ .name = owned_key, .value = val }) catch
                    return error.OutOfMemory;
            } else {
                try skipValue(d);
            },
            .ignore => try skipValue(d),
        }
    }

    inline for (S.fields, struct_fields, 0..) |sf, zf, i| {
        _ = sf;
        if (!seen[i]) {
            if (zf.defaultValue()) |default| {
                @field(result, zf.name) = default;
            } else if (@typeInfo(zf.type) == .optional) {
                @field(result, zf.name) = null;
            } else {
                d.ctx.issue(.{
                    .path = .field(zf.name),
                    .code = .required,
                    .message = "missing required field",
                });
            }
        }
    }
    return result;
}

/// Dynamic decode into core.Value (collected unknowns; internal/untagged
/// union buffering).
fn decodeValue(d: *Decoder) core.DecodeError!core.Value {
    switch (try readHeader(d)) {
        .int => |n| return .{ .int = std.math.cast(i64, n) orelse return error.Overflow },
        .float => |f| return .{ .float = f },
        .bool => |b| return .{ .bool = b },
        .nil => return .null,
        .str => |n| {
            const s = try d.readSlice(n);
            return .{ .string = if (d.options.memory == .owned)
                d.allocator.dupe(u8, s) catch return error.OutOfMemory
            else
                s };
        },
        .bin => |n| {
            const s = try d.readSlice(n);
            return .{ .bytes = if (d.options.memory == .owned)
                d.allocator.dupe(u8, s) catch return error.OutOfMemory
            else
                s };
        },
        .array => |n| {
            try d.enterNest();
            defer d.depth -= 1;
            const items = d.allocator.alloc(core.Value, n) catch return error.OutOfMemory;
            for (items) |*slot| slot.* = try decodeValue(d);
            return .{ .array = items };
        },
        .map => |n| {
            try d.enterNest();
            defer d.depth -= 1;
            const fields = d.allocator.alloc(core.FieldValue, n) catch return error.OutOfMemory;
            for (fields) |*slot| {
                const kn = switch (try readHeader(d)) {
                    .str => |kn| kn,
                    else => return error.UnexpectedToken,
                };
                const key = try d.readSlice(kn);
                slot.* = .{
                    .name = if (d.options.memory == .owned)
                        d.allocator.dupe(u8, key) catch return error.OutOfMemory
                    else
                        key,
                    .value = try decodeValue(d),
                };
            }
            return .{ .object = fields };
        },
    }
}

fn decodeUnion(comptime T: type, d: *Decoder) core.DecodeError!T {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval-msgpack: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    switch (comptime opts.union_tagging) {
        .external => {
            // unit variant as bare string, payload variant as 1-entry map
            switch (try readHeader(d)) {
                .str => |n| {
                    const s = try d.readSlice(n);
                    inline for (info.fields) |f| {
                        const wire = comptime core.naming.convert(opts.rename_all, f.name);
                        if (f.type == void) {
                            if (std.mem.eql(u8, s, wire)) return @unionInit(T, f.name, {});
                        }
                    }
                    return error.InvalidEnumTag;
                },
                .map => |n| {
                    if (n != 1) return error.UnexpectedToken;
                    const kn = switch (try readHeader(d)) {
                        .str => |kn| kn,
                        else => return error.UnexpectedToken,
                    };
                    const key = try d.readSlice(kn);
                    inline for (info.fields) |f| {
                        const wire = comptime core.naming.convert(opts.rename_all, f.name);
                        if (std.mem.eql(u8, key, wire)) {
                            if (f.type == void) {
                                return switch (try readHeader(d)) {
                                    .nil => @unionInit(T, f.name, {}),
                                    else => error.UnexpectedToken,
                                };
                            }
                            return @unionInit(T, f.name, try decodeAny(f.type, d, .{}));
                        }
                    }
                    return error.InvalidEnumTag;
                },
                else => return error.UnexpectedToken,
            }
        },
        .adjacent => {
            const n = switch (try readHeader(d)) {
                .map => |n| n,
                else => return error.UnexpectedToken,
            };
            if (n < 1 or n > 2) return error.UnexpectedToken;
            const tag_kn = switch (try readHeader(d)) {
                .str => |kn| kn,
                else => return error.UnexpectedToken,
            };
            if (!std.mem.eql(u8, try d.readSlice(tag_kn), opts.union_tag_field))
                return error.UnexpectedToken;
            const tag = try readStr(d, false);
            inline for (info.fields) |f| {
                const wire = comptime core.naming.convert(opts.rename_all, f.name);
                if (std.mem.eql(u8, tag, wire)) {
                    if (f.type == void) {
                        if (n != 1) return error.UnexpectedToken;
                        return @unionInit(T, f.name, {});
                    }
                    if (n != 2) return error.UnexpectedToken;
                    const ckn = switch (try readHeader(d)) {
                        .str => |kn| kn,
                        else => return error.UnexpectedToken,
                    };
                    if (!std.mem.eql(u8, try d.readSlice(ckn), opts.union_content_field))
                        return error.UnexpectedToken;
                    return @unionInit(T, f.name, try decodeAny(f.type, d, .{}));
                }
            }
            return error.InvalidEnumTag;
        },
        // Buffered: the tag key can appear anywhere in the map.
        .internal, .untagged => {
            const buffered = try decodeValue(d);
            return codec.fromValue(T, d.allocator, buffered);
        },
    }
}
