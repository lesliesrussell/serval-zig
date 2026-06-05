// serval-r4h
//! Schema-driven JSON decode. Tokenizes with std.json.Scanner, but typed
//! construction is driven by Schema(T): wire names from rename metadata,
//! presence tracking for ctx.has(), unknown-field policy, and validation
//! integration per DecodeOptions.validation.
//!
//! Memory: result data is allocated with the passed allocator (pass an
//! arena and free wholesale). With MemoryMode.owned, string values are
//! duplicated; otherwise unescaped strings borrow from the input buffer.

const std = @import("std");
const core = @import("serval-core");
const codec = @import("serval-codec");
const validate = @import("serval-validate");

pub const Error = core.DecodeError || error{ValidationFailed};

/// Typed fast path. Syntax problems, unknown fields (when rejected),
/// missing required fields, and validation failures all surface as errors.
/// Use decodeResult for the full path-aware report.
pub fn decode(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) Error!T {
    const result = try decodeResult(T, allocator, input, options);
    switch (result) {
        .ok => |v| return v,
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

// serval-0mq
/// Borrowed decode: result slices point into `input` wherever the bytes can
/// be used verbatim — the returned Borrowed(T) is valid ONLY while `input`
/// is. Escaped strings and non-u8 slices still allocate with `allocator`.
/// With `.validation = .none` and escape-free flat input, this performs
/// zero allocations.
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

/// Full decode pipeline: syntax errors land in .decode_error, shape and
/// constraint failures in .invalid (caller frees report.issues), success
/// in .ok.
pub fn decodeResult(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) error{OutOfMemory}!core.DecodeResult(T) {
    var ctx = core.ValidateContext.init(allocator);
    defer ctx.deinit();

    // serval-0mq: the scanner's nesting BitStack gets stack memory so value
    // decoding drives all heap use (zero-alloc borrowed decode stays zero).
    // The BitStack's ArrayList first grows to cache_line+1 bytes (129), so
    // 256 here buys ~1000 nesting levels; deeper input fails as OutOfMemory.
    var nesting_buf: [256]u8 = undefined;
    var nesting_fba = std.heap.FixedBufferAllocator.init(&nesting_buf);

    var d = Decoder{
        .scanner = std.json.Scanner.initCompleteInput(nesting_fba.allocator(), input),
        .allocator = allocator,
        .options = options,
        .ctx = &ctx,
        .present = .empty,
    };
    defer d.scanner.deinit();
    defer d.present.deinit(allocator);

    const value = decodeTop(T, &d) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .decode_error = e },
    };
    const tail = nextToken(&d) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .decode_error = e },
    };
    if (tail != .end_of_document) return .{ .decode_error = error.InvalidSyntax };

    // Shape issues (missing required, rejected unknown fields): the value
    // may contain undefined fields, so report without touching it further.
    if (ctx.issues.items.len > 0) {
        const issues = ctx.issues.toOwnedSlice(ctx.allocator) catch return error.OutOfMemory;
        return .{ .invalid = .{ .issues = issues } };
    }

    // TODO(serval): .lax should downgrade constraint failures to warnings;
    // for now it behaves like .strict.
    if (options.validation != .none) {
        const report = validate.check(T, &value, allocator, .{
            .present_fields = d.present.items,
        }) catch return error.OutOfMemory;
        if (!report.ok()) return .{ .invalid = report };
        allocator.free(report.issues);
    }

    return .{ .ok = value };
}

const Decoder = struct {
    scanner: std.json.Scanner,
    allocator: std.mem.Allocator,
    options: codec.DecodeOptions,
    ctx: *core.ValidateContext,
    /// Zig field names seen at the top level (comptime strings; no copies).
    present: std.ArrayList([]const u8),
};

fn decodeTop(comptime T: type, d: *Decoder) core.DecodeError!T {
    if (@typeInfo(T) == .@"struct") return decodeStruct(T, d, true);
    return decodeAny(T, d, .{});
}

// serval-vw4: type-level policies (bytes_policy, enum_tagging) come from the
// enclosing struct's options and flow down through optionals and slices.
fn decodeAny(
    comptime T: type,
    d: *Decoder,
    comptime parent: core.TypeOptions,
) core.DecodeError!T {
    switch (@typeInfo(T)) {
        .bool => return switch (try nextToken(d)) {
            .true => true,
            .false => false,
            else => error.UnexpectedToken,
        },
        .int => {
            const s = try numberSlice(d);
            return std.fmt.parseInt(T, s, 10) catch |e| switch (e) {
                error.Overflow => error.Overflow,
                error.InvalidCharacter => error.InvalidSyntax,
            };
        },
        .float => {
            const s = try numberSlice(d);
            return std.fmt.parseFloat(T, s) catch error.InvalidSyntax;
        },
        .optional => |o| {
            if (try peek(d) == .null) {
                _ = try nextToken(d);
                return null;
            }
            return try decodeAny(o.child, d, parent);
        },
        .@"enum" => switch (parent.enum_tagging) {
            .name => {
                const s = try stringSlice(d, false);
                return std.meta.stringToEnum(T, s) orelse error.InvalidEnumTag;
            },
            .value => {
                const s = try numberSlice(d);
                const n = std.fmt.parseInt(@typeInfo(T).@"enum".tag_type, s, 10) catch
                    return error.InvalidEnumTag;
                return std.enums.fromInt(T, n) orelse error.InvalidEnumTag;
            },
        },
        .pointer => |p| {
            if (p.size != .slice)
                @compileError("serval-json: unsupported pointer type " ++ @typeName(T));
            if (p.child == u8 and parent.bytes_policy == .string)
                return try stringSlice(d, true);
            return try decodeSlice(p.child, d, parent);
        },
        .@"struct" => return decodeStruct(T, d, false),
        // serval-x9g
        .@"union" => return decodeUnion(T, d),
        else => @compileError("serval-json: unsupported type " ++ @typeName(T)),
    }
}

// serval-x9g
fn decodeUnion(comptime T: type, d: *Decoder) core.DecodeError!T {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval-json: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    return switch (comptime opts.union_tagging) {
        .external => decodeUnionExternal(T, d, opts),
        .adjacent => decodeUnionAdjacent(T, d, opts),
        // Decode can't backtrack the streaming scanner to find the tag mid-
        // object; lands with the buffered-Value path (serval-ee8).
        .internal, .untagged => @compileError(
            "serval-json: " ++ @tagName(opts.union_tagging) ++
                " union tagging not yet supported: " ++ @typeName(T),
        ),
    };
}

// serval-x9g
fn decodeUnionExternal(
    comptime T: type,
    d: *Decoder,
    comptime opts: core.TypeOptions,
) core.DecodeError!T {
    switch (try peek(d)) {
        // unit variant: bare string
        .string => {
            const s = try stringSlice(d, false);
            inline for (@typeInfo(T).@"union".fields) |f| {
                const wire = comptime core.naming.convert(opts.rename_all, f.name);
                if (f.type == void) {
                    if (std.mem.eql(u8, s, wire)) return @unionInit(T, f.name, {});
                }
            }
            return error.InvalidEnumTag;
        },
        .object_begin => {
            _ = try nextToken(d);
            const key = switch (try nextToken(d)) {
                .string, .allocated_string => |s| s,
                else => return error.UnexpectedToken,
            };
            const result = blk: {
                inline for (@typeInfo(T).@"union".fields) |f| {
                    const wire = comptime core.naming.convert(opts.rename_all, f.name);
                    if (std.mem.eql(u8, key, wire)) {
                        if (f.type == void) {
                            switch (try nextToken(d)) {
                                .null => break :blk @unionInit(T, f.name, {}),
                                else => return error.UnexpectedToken,
                            }
                        }
                        break :blk @unionInit(T, f.name, try decodeAny(f.type, d, .{}));
                    }
                }
                return error.InvalidEnumTag;
            };
            return switch (try nextToken(d)) {
                .object_end => result,
                else => error.UnexpectedToken,
            };
        },
        else => return error.UnexpectedToken,
    }
}

// serval-x9g
fn decodeUnionAdjacent(
    comptime T: type,
    d: *Decoder,
    comptime opts: core.TypeOptions,
) core.DecodeError!T {
    switch (try nextToken(d)) {
        .object_begin => {},
        else => return error.UnexpectedToken,
    }
    const tag_key = switch (try nextToken(d)) {
        .string, .allocated_string => |s| s,
        else => return error.UnexpectedToken,
    };
    if (!std.mem.eql(u8, tag_key, opts.union_tag_field)) return error.UnexpectedToken;
    const tag = switch (try nextToken(d)) {
        .string, .allocated_string => |s| s,
        else => return error.UnexpectedToken,
    };
    inline for (@typeInfo(T).@"union".fields) |f| {
        const wire = comptime core.naming.convert(opts.rename_all, f.name);
        if (std.mem.eql(u8, tag, wire)) {
            if (f.type == void) {
                return switch (try nextToken(d)) {
                    .object_end => @unionInit(T, f.name, {}),
                    else => error.UnexpectedToken,
                };
            }
            const content_key = switch (try nextToken(d)) {
                .string, .allocated_string => |s| s,
                else => return error.UnexpectedToken,
            };
            if (!std.mem.eql(u8, content_key, opts.union_content_field))
                return error.UnexpectedToken;
            const payload = try decodeAny(f.type, d, .{});
            return switch (try nextToken(d)) {
                .object_end => @unionInit(T, f.name, payload),
                else => error.UnexpectedToken,
            };
        }
    }
    return error.InvalidEnumTag;
}

fn decodeStruct(comptime T: type, d: *Decoder, comptime is_top: bool) core.DecodeError!T {
    switch (try nextToken(d)) {
        .object_begin => {},
        else => return error.UnexpectedToken,
    }
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;
    var seen = [_]bool{false} ** struct_fields.len;

    key_loop: while (true) {
        const key = switch (try nextToken(d)) {
            .object_end => break,
            .string, .allocated_string => |s| s,
            else => return error.UnexpectedToken,
        };
        inline for (S.fields, struct_fields, 0..) |sf, zf, i| {
            if (std.mem.eql(u8, key, sf.wire_name)) {
                @field(result, zf.name) = try decodeAny(zf.type, d, S.options);
                seen[i] = true;
                // serval-0mq: presence only feeds validation — skip the
                // allocation entirely when validation is off.
                if (is_top and d.options.validation != .none) {
                    d.present.append(d.allocator, zf.name) catch return error.OutOfMemory;
                }
                continue :key_loop;
            }
        }
        switch (d.options.unknown_fields) {
            .reject => d.ctx.issue(.{
                .path = .root,
                .code = .unknown_field,
                .message = "unknown field in input",
            }),
            // TODO(serval): .collect should stash into a Value map once the
            // dynamic path lands; treated as .ignore for now.
            .ignore, .collect => {},
        }
        d.scanner.skipValue() catch |e| return mapScanError(e);
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

fn decodeSlice(
    comptime Child: type,
    d: *Decoder,
    comptime parent: core.TypeOptions,
) core.DecodeError![]const Child {
    switch (try nextToken(d)) {
        .array_begin => {},
        else => return error.UnexpectedToken,
    }
    var list: std.ArrayList(Child) = .empty;
    defer list.deinit(d.allocator);
    while (true) {
        if (try peek(d) == .array_end) {
            _ = try nextToken(d);
            break;
        }
        const item = try decodeAny(Child, d, parent);
        list.append(d.allocator, item) catch return error.OutOfMemory;
    }
    return list.toOwnedSlice(d.allocator) catch return error.OutOfMemory;
}

fn nextToken(d: *Decoder) core.DecodeError!std.json.Token {
    return d.scanner.nextAlloc(d.allocator, .alloc_if_needed) catch |e| mapScanError(e);
}

fn peek(d: *Decoder) core.DecodeError!std.json.TokenType {
    return d.scanner.peekNextTokenType() catch |e| mapScanError(e);
}

fn numberSlice(d: *Decoder) core.DecodeError![]const u8 {
    return switch (try nextToken(d)) {
        .number, .allocated_number => |s| s,
        else => error.UnexpectedToken,
    };
}

/// `dupe_for_owned`: with MemoryMode.owned, unescaped string tokens (which
/// borrow from the input buffer) are duplicated so the result outlives it.
fn stringSlice(d: *Decoder, dupe_for_owned: bool) core.DecodeError![]const u8 {
    return switch (try nextToken(d)) {
        .string => |s| if (dupe_for_owned and d.options.memory == .owned)
            d.allocator.dupe(u8, s) catch error.OutOfMemory
        else
            s,
        .allocated_string => |s| s,
        else => error.UnexpectedToken,
    };
}

fn mapScanError(e: anyerror) core.DecodeError {
    return switch (e) {
        // Note: covers both value-allocator OOM (escaped strings) and the
        // fixed nesting buffer overflowing past 1024 levels.
        error.OutOfMemory => error.OutOfMemory,
        error.UnexpectedEndOfInput => error.UnexpectedEndOfInput,
        else => error.InvalidSyntax,
    };
}
