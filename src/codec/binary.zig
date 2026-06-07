// serval-2wi
//! Shared binary-backend template. MessagePack and CBOR differ only in
//! how one value's header is read and how scalars/headers are written —
//! everything above the wire bytes (typed construction, presence,
//! unknown-field policy, coercion, transforms, unions, depth cap,
//! validation pipeline) is generated here.
//!
//! Wire contract:
//!   decode: `fn readHeader(d: anytype) core.DecodeError!Header`
//!           (d provides readByte/readSlice/readBig), `null_byte: u8`
//!   encode: writeNull, writeBool, writeInt, writeFloat, writeStr,
//!           writeBin, writeArrayHeader, writeMapHeader — all taking
//!           `*std.Io.Writer`.

const std = @import("std");
const core = @import("serval-core");
const validate = @import("serval-validate");
const options_mod = @import("options.zig");
const borrow = @import("borrow.zig");
const from_value = @import("decode.zig");
// serval-sj2
const contract = @import("codec.zig");

/// Wire-neutral classification of one binary value's header.
pub const Header = union(enum) {
    int: i128,
    float: f64,
    bool: bool,
    nil,
    str: usize,
    bin: usize,
    array: usize,
    map: usize,
};

/// Containers recurse — a 1-byte array header per level would otherwise
/// turn input length into stack depth.
pub const max_nesting = 256;

pub fn Backend(comptime Wire: type) type {
    return struct {
        pub const Error = core.DecodeError || error{ValidationFailed};

        // serval-xx5: the template provides the full capability set.
        pub const capabilities: @import("codec.zig").Capabilities = .{
            .presence_tracking = true,
            .borrowed_mode = true,
            .coercion = true,
            .rename_metadata = true,
            .shape_issue_fidelity = true,
            .collect_unknown = true,
            .projection = true,
            .union_external = .streaming,
            .union_adjacent = .streaming,
            .union_internal = .buffered,
            .union_untagged = .buffered,
        };

        const DecodeOptions = options_mod.DecodeOptions;
        const EncodeOptions = options_mod.EncodeOptions;

        // --- Decode ---------------------------------------------------

        /// Typed fast path; see decodeResult for the report-carrying
        /// pipeline.
        pub fn decode(
            comptime T: type,
            allocator: std.mem.Allocator,
            input: []const u8,
            options: DecodeOptions,
        ) Error!T {
            const result = try decodeResult(T, allocator, input, options);
            return unwrapResult(T, allocator, result);
        }

        /// Borrowed decode: result slices point into `input` — valid only
        /// while it is. Zero allocations for flat structs with
        /// `.validation = .none`.
        pub fn decodeBorrowed(
            comptime T: type,
            allocator: std.mem.Allocator,
            input: []const u8,
            options: DecodeOptions,
        ) Error!borrow.Borrowed(T) {
            var opts = options;
            opts.memory = .borrowed;
            // serval-47j: observable borrowing — count forced allocations.
            var counting = borrow.CountingAllocator{ .child = allocator };
            const value = try decode(T, counting.allocator(), input, opts);
            return .{ .value = value, .allocated = counting.count > 0 };
        }

        /// Streaming decode: slurps the reader, then runs the normal
        /// pipeline. Forces MemoryMode.owned — the slurped buffer is freed
        /// before returning, so borrowed results would dangle.
        pub fn decodeFromReader(
            comptime T: type,
            allocator: std.mem.Allocator,
            io_reader: *std.Io.Reader,
            options: DecodeOptions,
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

        /// Public dynamic decode: the whole document as a format-neutral
        /// core.Value tree. Memory rules match decode(); pass an arena.
        pub fn decodeValueSlice(
            allocator: std.mem.Allocator,
            input: []const u8,
            options: DecodeOptions,
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
            options: DecodeOptions,
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

            return pipelineTail(T, allocator, options, &d, &ctx, value);
        }

        // serval-54c
        /// Partial decode: P is a SUBSET of the document's fields. The
        /// top-level scan EARLY-EXITS once every field of P has been seen —
        /// the rest of the document is never parsed (and may be invalid or
        /// truncated past that point). Validation and presence apply to P.
        pub fn decodeProjection(
            comptime P: type,
            allocator: std.mem.Allocator,
            input: []const u8,
            options: DecodeOptions,
        ) Error!P {
            var opts = options;
            opts.unknown_fields = .ignore;

            var ctx = core.ValidateContext.init(allocator);
            defer ctx.deinit();

            var d = Decoder{
                .buf = input,
                .allocator = allocator,
                .options = opts,
                .ctx = &ctx,
                .present = .empty,
                .projection = true,
            };
            defer d.present.deinit(allocator);
            defer d.unknown.deinit(allocator);

            const value = decodeTop(P, &d) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return e,
            };
            // no end-of-input check — projection abandons the document
            const result = try pipelineTail(P, allocator, opts, &d, &ctx, value);
            return unwrapResult(P, allocator, result);
        }

        // serval-54c: shape/unknown/validation tail shared by full decode
        // and projection.
        fn pipelineTail(
            comptime T: type,
            allocator: std.mem.Allocator,
            options: DecodeOptions,
            d: *Decoder,
            ctx: *core.ValidateContext,
            value: T,
        ) error{OutOfMemory}!core.DecodeResult(T) {
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
                report.deinit(allocator);
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
                    ok.warnings.deinit(allocator);
                    allocator.free(ok.unknown);
                    return ok.value;
                },
                .invalid => |report| {
                    defer report.deinit(allocator);
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

        pub const Decoder = struct {
            buf: []const u8,
            pos: usize = 0,
            allocator: std.mem.Allocator,
            options: DecodeOptions,
            ctx: *core.ValidateContext,
            /// Zig field names seen at the top level (comptime strings).
            present: std.ArrayList([]const u8),
            /// Top-level unknown fields gathered under .collect.
            unknown: std.ArrayList(core.FieldValue) = .empty,
            depth: usize = 0,
            // serval-54c
            /// Projection mode: struct decode early-exits once every field
            /// of the target is seen.
            projection: bool = false,

            fn enterNest(d: *Decoder) core.DecodeError!void {
                d.depth += 1;
                if (d.depth > max_nesting) return error.InvalidSyntax;
            }

            pub fn readByte(d: *Decoder) core.DecodeError!u8 {
                if (d.pos >= d.buf.len) return error.UnexpectedEndOfInput;
                defer d.pos += 1;
                return d.buf[d.pos];
            }

            pub fn readSlice(d: *Decoder, n: usize) core.DecodeError![]const u8 {
                if (d.buf.len - d.pos < n) return error.UnexpectedEndOfInput;
                defer d.pos += n;
                return d.buf[d.pos .. d.pos + n];
            }

            pub fn readBig(d: *Decoder, comptime U: type) core.DecodeError!U {
                const bytes = try d.readSlice(@divExact(@bitSizeOf(U), 8));
                return std.mem.readInt(U, bytes[0..@divExact(@bitSizeOf(U), 8)], .big);
            }
        };

        fn decodeTop(comptime T: type, d: *Decoder) core.DecodeError!T {
            if (@typeInfo(T) == .@"struct") return decodeStruct(T, d, true);
            return decodeAny(T, d, .{});
        }

        fn skipValue(d: *Decoder) core.DecodeError!void {
            switch (try Wire.readHeader(d)) {
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
            const n = switch (try Wire.readHeader(d)) {
                .str, .bin => |n| n,
                else => return error.UnexpectedToken,
            };
            const s = try d.readSlice(n);
            if (dupe_for_owned and d.options.memory == .owned) {
                return d.allocator.dupe(u8, s) catch error.OutOfMemory;
            }
            return s;
        }

        /// String-typed field value: a str/bin item, or under aggressive
        /// coercion a formatted scalar.
        fn stringValue(d: *Decoder) core.DecodeError![]const u8 {
            switch (try Wire.readHeader(d)) {
                .str, .bin => |n| {
                    const s = try d.readSlice(n);
                    return if (d.options.memory == .owned)
                        d.allocator.dupe(u8, s) catch error.OutOfMemory
                    else
                        s;
                },
                .int => |n| {
                    if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                    return std.fmt.allocPrint(d.allocator, "{d}", .{n}) catch error.OutOfMemory;
                },
                .float => |f| {
                    if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                    return std.fmt.allocPrint(d.allocator, "{d}", .{f}) catch error.OutOfMemory;
                },
                .bool => |b| {
                    if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                    return if (b) "true" else "false";
                },
                else => return error.UnexpectedToken,
            }
        }

        fn decodeAny(
            comptime T: type,
            d: *Decoder,
            comptime parent: core.TypeOptions,
        ) core.DecodeError!T {
            switch (@typeInfo(T)) {
                // Scalar branches accept coerced inputs per
                // DecodeOptions.coercion (see validate/coercion.zig).
                .bool => switch (try Wire.readHeader(d)) {
                    .bool => |b| return b,
                    .str => |n| {
                        const s = try d.readSlice(n);
                        if (d.options.coercion == .none) return error.UnexpectedToken;
                        return validate.coercion.boolFromString(s) orelse error.UnexpectedToken;
                    },
                    .int => |n| {
                        if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                        return validate.coercion.boolFromInt(n) orelse error.UnexpectedToken;
                    },
                    else => return error.UnexpectedToken,
                },
                .int => switch (try Wire.readHeader(d)) {
                    .int => |n| return std.math.cast(T, n) orelse error.Overflow,
                    .str => |n| {
                        const s = try d.readSlice(n);
                        if (d.options.coercion == .none) return error.UnexpectedToken;
                        return validate.coercion.intFromString(T, s) orelse error.UnexpectedToken;
                    },
                    .float => |f| {
                        if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                        return validate.coercion.intFromFloat(T, f) orelse error.Overflow;
                    },
                    .bool => |b| {
                        if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                        return @intFromBool(b);
                    },
                    else => return error.UnexpectedToken,
                },
                .float => switch (try Wire.readHeader(d)) {
                    .float => |f| return @floatCast(f),
                    .int => |n| return @floatFromInt(n),
                    .str => |n| {
                        const s = try d.readSlice(n);
                        if (d.options.coercion == .none) return error.UnexpectedToken;
                        return validate.coercion.floatFromString(T, s) orelse error.UnexpectedToken;
                    },
                    else => return error.UnexpectedToken,
                },
                .optional => |o| {
                    if (d.pos < d.buf.len and d.buf[d.pos] == Wire.null_byte) {
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
                    .value => return switch (try Wire.readHeader(d)) {
                        .int => |n| std.enums.fromInt(T, n) orelse error.InvalidEnumTag,
                        else => error.UnexpectedToken,
                    },
                },
                .pointer => |p| {
                    if (p.size != .slice)
                        @compileError("serval binary backend: unsupported pointer type " ++ @typeName(T));
                    // str/bin accepted interchangeably for []u8.
                    if (p.child == u8) return try stringValue(d);
                    return try decodeSlice(p.child, d, parent);
                },
                .@"struct" => return decodeStruct(T, d, false),
                .@"union" => return decodeUnion(T, d),
                else => @compileError("serval binary backend: unsupported type " ++ @typeName(T)),
            }
        }

        fn decodeSlice(
            comptime Child: type,
            d: *Decoder,
            comptime parent: core.TypeOptions,
        ) core.DecodeError![]const Child {
            const n = switch (try Wire.readHeader(d)) {
                .array => |n| n,
                else => return error.UnexpectedToken,
            };
            try d.enterNest();
            defer d.depth -= 1;
            const out = d.allocator.alloc(Child, n) catch return error.OutOfMemory;
            for (out, 0..) |*slot, i| {
                const descends = comptime core.type_info.containsStruct(Child);
                if (descends) d.ctx.pushPath(.{ .index = i });
                slot.* = try decodeAny(Child, d, parent);
                if (descends) d.ctx.popPath();
            }
            return out;
        }

        fn decodeStruct(comptime T: type, d: *Decoder, comptime is_top: bool) core.DecodeError!T {
            const n = switch (try Wire.readHeader(d)) {
                .map => |n| n,
                else => return error.UnexpectedToken,
            };
            try d.enterNest();
            defer d.depth -= 1;
            const S = core.schemaOf(T);
            const struct_fields = @typeInfo(T).@"struct".fields;
            var result: T = undefined;
            var seen = [_]bool{false} ** struct_fields.len;
            // serval-54c
            var seen_count: usize = 0;

            key_loop: for (0..n) |_| {
                const key = blk: {
                    const kn = switch (try Wire.readHeader(d)) {
                        .str => |kn| kn,
                        else => return error.UnexpectedToken,
                    };
                    break :blk try d.readSlice(kn);
                };
                inline for (S.fields, struct_fields, 0..) |sf, zf, i| {
                    if (std.mem.eql(u8, key, sf.wire_name)) {
                        // Nested shape issues get full paths; gated so flat
                        // decodes stay allocation-free.
                        const descends = comptime core.type_info.containsStruct(zf.type);
                        if (descends) d.ctx.pushPath(.{ .field = zf.name });
                        @field(result, zf.name) = try decodeAny(zf.type, d, S.options);
                        if (descends) d.ctx.popPath();
                        try validate.coercion.applyStringTransforms(sf.meta, zf.type, &@field(result, zf.name), d.allocator);
                        // serval-54c
                        if (!seen[i]) seen_count += 1;
                        seen[i] = true;
                        if (is_top and d.options.validation != .none) {
                            d.present.append(d.allocator, zf.name) catch return error.OutOfMemory;
                        }
                        // serval-54c: projection — all fields of P seen.
                        if (is_top and d.projection and seen_count == struct_fields.len) break :key_loop;
                        continue :key_loop;
                    }
                }
                switch (d.options.unknown_fields) {
                    .reject => {
                        d.ctx.issue(.{
                            .path = .root,
                            .code = .unknown_field,
                            .message = "unknown field",
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

        /// Dynamic decode into core.Value (collected unknowns;
        /// internal/untagged union buffering).
        fn decodeValue(d: *Decoder) core.DecodeError!core.Value {
            switch (try Wire.readHeader(d)) {
                // serval-dfo (D1): Value.int is i128 — no loss point here.
                .int => |n| return .{ .int = n },
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
                        const kn = switch (try Wire.readHeader(d)) {
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
                @compileError("serval binary backend: untagged Zig unions unsupported: " ++ @typeName(T));
            const opts = core.schemaOf(T).options;
            switch (comptime opts.union_tagging) {
                .external => {
                    // unit variant as bare string, payload variant as
                    // 1-entry map
                    switch (try Wire.readHeader(d)) {
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
                            const kn = switch (try Wire.readHeader(d)) {
                                .str => |kn| kn,
                                else => return error.UnexpectedToken,
                            };
                            const key = try d.readSlice(kn);
                            inline for (info.fields) |f| {
                                const wire = comptime core.naming.convert(opts.rename_all, f.name);
                                if (std.mem.eql(u8, key, wire)) {
                                    if (f.type == void) {
                                        return switch (try Wire.readHeader(d)) {
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
                    const n = switch (try Wire.readHeader(d)) {
                        .map => |n| n,
                        else => return error.UnexpectedToken,
                    };
                    if (n < 1 or n > 2) return error.UnexpectedToken;
                    const tag_kn = switch (try Wire.readHeader(d)) {
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
                            const ckn = switch (try Wire.readHeader(d)) {
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
                    return from_value.fromValueCoerce(T, d.allocator, buffered, d.options.coercion);
                },
            }
        }

        // --- Encode ---------------------------------------------------

        /// Encode `value` to an owned buffer. Caller frees with
        /// `allocator`.
        pub fn encodeAlloc(
            comptime T: type,
            allocator: std.mem.Allocator,
            value: T,
            options: EncodeOptions,
        ) error{OutOfMemory}![]u8 {
            var aw: std.Io.Writer.Allocating = .init(allocator);
            defer aw.deinit();
            encodeToWriter(T, value, options, &aw.writer) catch return error.OutOfMemory;
            return aw.toOwnedSlice();
        }

        /// Encode `value` directly to a std.Io.Writer.
        /// EncodeOptions.pretty is meaningless for binary formats.
        pub fn encodeToWriter(
            comptime T: type,
            value: T,
            options: EncodeOptions,
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try encodeAny(T, value, writer, .{}, options.canonical);
        }

        /// Exact encoded length without producing output.
        pub fn measureEncodedLen(
            comptime T: type,
            value: T,
            options: EncodeOptions,
        ) usize {
            var counter: std.Io.Writer.Discarding = .init(&.{});
            encodeToWriter(T, value, options, &counter.writer) catch unreachable;
            return @intCast(counter.count + counter.writer.end);
        }

        fn encodeAny(
            comptime T: type,
            v: T,
            w: *std.Io.Writer,
            comptime parent: core.TypeOptions,
            canonical: bool,
        ) std.Io.Writer.Error!void {
            switch (@typeInfo(T)) {
                .bool => try Wire.writeBool(w, v),
                .int, .comptime_int => try Wire.writeInt(w, v),
                .float, .comptime_float => try Wire.writeFloat(w, v),
                .optional => |o| {
                    if (v) |payload| {
                        try encodeAny(o.child, payload, w, parent, canonical);
                    } else {
                        try Wire.writeNull(w);
                    }
                },
                .@"enum" => switch (parent.enum_tagging) {
                    .name => try Wire.writeStr(w, @tagName(v)),
                    .value => try Wire.writeInt(w, @intFromEnum(v)),
                },
                .pointer => |p| {
                    if (p.size != .slice)
                        @compileError("serval binary backend: unsupported pointer type " ++ @typeName(T));
                    if (p.child == u8 and parent.bytes_policy == .string) {
                        try Wire.writeStr(w, v);
                    } else if (p.child == u8) {
                        try Wire.writeBin(w, v);
                    } else {
                        try Wire.writeArrayHeader(w, v.len);
                        for (v) |item| try encodeAny(p.child, item, w, parent, canonical);
                    }
                },
                .@"struct" => try encodeStruct(T, v, w, canonical),
                .@"union" => try encodeUnion(T, v, w, canonical),
                else => @compileError("serval binary backend: unsupported type " ++ @typeName(T)),
            }
        }

        fn encodeStruct(comptime T: type, v: T, w: *std.Io.Writer, canonical: bool) std.Io.Writer.Error!void {
            const S = core.schemaOf(T);
            const struct_fields = @typeInfo(T).@"struct".fields;
            try Wire.writeMapHeader(w, struct_fields.len);
            if (canonical) {
                // serval-sj2: comptime-sorted key order per wire format.
                const wire_names = comptime blk: {
                    var names: [S.fields.len][]const u8 = undefined;
                    for (S.fields, 0..) |sf, i| names[i] = sf.wire_name;
                    break :blk names;
                };
                inline for (comptime contract.sortedKeyIndices(&wire_names, Wire.canonical_key_order)) |fi| {
                    try Wire.writeStr(w, S.fields[fi].wire_name);
                    try encodeAny(struct_fields[fi].type, @field(v, struct_fields[fi].name), w, S.options, canonical);
                }
            } else {
                inline for (S.fields, struct_fields) |sf, zf| {
                    try Wire.writeStr(w, sf.wire_name);
                    try encodeAny(zf.type, @field(v, zf.name), w, S.options, canonical);
                }
            }
        }

        fn encodeUnion(comptime T: type, v: T, w: *std.Io.Writer, canonical: bool) std.Io.Writer.Error!void {
            const info = @typeInfo(T).@"union";
            if (info.tag_type == null)
                @compileError("serval binary backend: untagged Zig unions unsupported: " ++ @typeName(T));
            const opts = core.schemaOf(T).options;
            switch (comptime opts.union_tagging) {
                .external => switch (v) {
                    inline else => |payload, tag| {
                        const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                        if (@TypeOf(payload) == void) {
                            try Wire.writeStr(w, wire);
                        } else {
                            try Wire.writeMapHeader(w, 1);
                            try Wire.writeStr(w, wire);
                            try encodeAny(@TypeOf(payload), payload, w, .{}, canonical);
                        }
                    },
                },
                .adjacent => switch (v) {
                    inline else => |payload, tag| {
                        const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                        const has_content = @TypeOf(payload) != void;
                        // serval-sj2
                        const content_first = comptime contract.keyLess(Wire.canonical_key_order, opts.union_content_field, opts.union_tag_field);
                        try Wire.writeMapHeader(w, if (has_content) 2 else 1);
                        if (canonical and has_content and content_first) {
                            try Wire.writeStr(w, opts.union_content_field);
                            try encodeAny(@TypeOf(payload), payload, w, .{}, canonical);
                            try Wire.writeStr(w, opts.union_tag_field);
                            try Wire.writeStr(w, wire);
                        } else {
                            try Wire.writeStr(w, opts.union_tag_field);
                            try Wire.writeStr(w, wire);
                            if (has_content) {
                                try Wire.writeStr(w, opts.union_content_field);
                                try encodeAny(@TypeOf(payload), payload, w, .{}, canonical);
                            }
                        }
                    },
                },
                .internal => switch (v) {
                    inline else => |payload, tag| {
                        const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                        const P = @TypeOf(payload);
                        if (P == void) {
                            try Wire.writeMapHeader(w, 1);
                            try Wire.writeStr(w, opts.union_tag_field);
                            try Wire.writeStr(w, wire);
                        } else {
                            if (@typeInfo(P) != .@"struct")
                                @compileError("serval binary backend: internal union tagging requires struct or void payloads: " ++ @typeName(T));
                            const PS = core.schemaOf(P);
                            const pfields = @typeInfo(P).@"struct".fields;
                            try Wire.writeMapHeader(w, 1 + pfields.len);
                            if (canonical) {
                                // serval-sj2: tag key sorted among payload keys.
                                const keys = comptime blk: {
                                    var arr: [1 + PS.fields.len][]const u8 = undefined;
                                    arr[0] = opts.union_tag_field;
                                    for (PS.fields, 0..) |sf, i| arr[1 + i] = sf.wire_name;
                                    break :blk arr;
                                };
                                inline for (comptime contract.sortedKeyIndices(&keys, Wire.canonical_key_order)) |ki| {
                                    if (ki == 0) {
                                        try Wire.writeStr(w, opts.union_tag_field);
                                        try Wire.writeStr(w, wire);
                                    } else {
                                        try Wire.writeStr(w, PS.fields[ki - 1].wire_name);
                                        try encodeAny(pfields[ki - 1].type, @field(payload, pfields[ki - 1].name), w, PS.options, canonical);
                                    }
                                }
                            } else {
                                try Wire.writeStr(w, opts.union_tag_field);
                                try Wire.writeStr(w, wire);
                                inline for (PS.fields, pfields) |sf, zf| {
                                    try Wire.writeStr(w, sf.wire_name);
                                    try encodeAny(zf.type, @field(payload, zf.name), w, PS.options, canonical);
                                }
                            }
                        }
                    },
                },
                .untagged => switch (v) {
                    inline else => |payload| {
                        if (@TypeOf(payload) == void) {
                            try Wire.writeNull(w);
                        } else {
                            try encodeAny(@TypeOf(payload), payload, w, .{}, canonical);
                        }
                    },
                },
            }
        }
    };
}
