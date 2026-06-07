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
    return unwrapResult(T, allocator, result);
}

// serval-x09: report→error mapping shared by the typed fast paths.
fn unwrapResult(
    comptime T: type,
    allocator: std.mem.Allocator,
    result: core.DecodeResult(T),
) Error!T {
    switch (result) {
        // serval-w98: fast path drops lax warnings and collected unknowns.
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
    // serval-47j: observable borrowing — count forced allocations.
    var counting = codec.borrow.CountingAllocator{ .child = allocator };
    const value = try decode(T, counting.allocator(), input, opts);
    return .{ .value = value, .allocated = counting.count > 0 };
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

    var d = Decoder(std.json.Scanner){
        .scanner = std.json.Scanner.initCompleteInput(nesting_fba.allocator(), input),
        .allocator = allocator,
        .options = options,
        .ctx = &ctx,
        .present = .empty,
    };
    defer d.scanner.deinit();
    defer d.present.deinit(allocator);
    // serval-ee8: frees list storage only; collected Value trees are
    // reachable from the .ok result, or (on invalid/error paths) are
    // expected to live in a caller arena.
    defer d.unknown.deinit(allocator);

    return finishDecode(T, allocator, options, &d, &ctx, true);
}

// serval-l3p
/// Public dynamic decode: the whole document as a format-neutral
/// core.Value tree (schema-driven workflows, diagnostics, transcoding).
/// Memory rules match decode(); pass an arena.
pub fn decodeValueSlice(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) core.DecodeError!core.Value {
    var ctx = core.ValidateContext.init(allocator);
    defer ctx.deinit();

    var nesting_buf: [256]u8 = undefined;
    var nesting_fba = std.heap.FixedBufferAllocator.init(&nesting_buf);

    var d = Decoder(std.json.Scanner){
        .scanner = std.json.Scanner.initCompleteInput(nesting_fba.allocator(), input),
        .allocator = allocator,
        .options = options,
        .ctx = &ctx,
        .present = .empty,
    };
    defer d.scanner.deinit();
    defer d.present.deinit(allocator);
    defer d.unknown.deinit(allocator);

    const v = try decodeValue(&d);
    if (try nextToken(&d) != .end_of_document) return error.InvalidSyntax;
    return v;
}

// serval-54c
/// Partial decode: P is a SUBSET of the document's fields (deep
/// projection = nested subset structs). Unknown fields are skipped at
/// the token level, and the top-level scan EARLY-EXITS once every field
/// of P has been seen — the rest of the document is never parsed (and
/// may even be invalid). Validation and presence apply to P as usual.
pub fn decodeProjection(
    comptime P: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) Error!P {
    var opts = options;
    opts.unknown_fields = .ignore;

    var ctx = core.ValidateContext.init(allocator);
    defer ctx.deinit();

    var nesting_buf: [256]u8 = undefined;
    var nesting_fba = std.heap.FixedBufferAllocator.init(&nesting_buf);

    var d = Decoder(std.json.Scanner){
        .scanner = std.json.Scanner.initCompleteInput(nesting_fba.allocator(), input),
        .allocator = allocator,
        .options = opts,
        .ctx = &ctx,
        .present = .empty,
        .projection = true,
    };
    defer d.scanner.deinit();
    defer d.present.deinit(allocator);
    defer d.unknown.deinit(allocator);

    const result = try finishDecode(P, allocator, opts, &d, &ctx, false);
    return unwrapResult(P, allocator, result);
}

// serval-x09
/// Streaming variants of decode/decodeResult over std.Io.Reader. The
/// reader is tokenized incrementally via std.json.Reader; nesting
/// bookkeeping uses the value allocator (no zero-alloc guarantee here).
pub fn decodeFromReader(
    comptime T: type,
    allocator: std.mem.Allocator,
    io_reader: *std.Io.Reader,
    options: codec.DecodeOptions,
) Error!T {
    const result = try decodeResultFromReader(T, allocator, io_reader, options);
    return unwrapResult(T, allocator, result);
}

// serval-x09
pub fn decodeResultFromReader(
    comptime T: type,
    allocator: std.mem.Allocator,
    io_reader: *std.Io.Reader,
    options: codec.DecodeOptions,
) error{OutOfMemory}!core.DecodeResult(T) {
    var ctx = core.ValidateContext.init(allocator);
    defer ctx.deinit();

    var d = Decoder(std.json.Reader){
        .scanner = std.json.Reader.init(allocator, io_reader),
        .allocator = allocator,
        .options = options,
        .ctx = &ctx,
        .present = .empty,
    };
    defer d.scanner.deinit();
    defer d.present.deinit(allocator);
    defer d.unknown.deinit(allocator);

    return finishDecode(T, allocator, options, &d, &ctx, true);
}

// serval-x09: pipeline shared by slice and reader entry points.
fn finishDecode(
    comptime T: type,
    allocator: std.mem.Allocator,
    options: codec.DecodeOptions,
    d: anytype,
    ctx: *core.ValidateContext,
    comptime check_tail: bool,
) error{OutOfMemory}!core.DecodeResult(T) {
    const value = decodeTop(T, d) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .decode_error = e },
    };
    // serval-54c: projection abandons the document mid-scan.
    if (check_tail) {
        const tail = nextToken(d) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{ .decode_error = e },
        };
        if (tail != .end_of_document) return .{ .decode_error = error.InvalidSyntax };
    }

    // Shape issues (missing required, rejected unknown fields): the value
    // may contain undefined fields, so report without touching it further.
    if (ctx.issues.items.len > 0) {
        const issues = ctx.issues.toOwnedSlice(ctx.allocator) catch return error.OutOfMemory;
        return .{ .invalid = .{ .issues = issues } };
    }

    // serval-ee8
    const unknown = d.unknown.toOwnedSlice(allocator) catch return error.OutOfMemory;

    if (options.validation != .none) {
        const report = validate.check(T, &value, allocator, .{
            .present_fields = d.present.items,
        }) catch return error.OutOfMemory;
        if (!report.ok()) {
            // serval-w98: lax downgrades constraint failures to warnings on ok.
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

// serval-x09: generic over the token source — std.json.Scanner for slices,
// std.json.Reader for streaming; both expose the same token API.
fn Decoder(comptime Source: type) type {
    return struct {
        scanner: Source,
        allocator: std.mem.Allocator,
        options: codec.DecodeOptions,
        ctx: *core.ValidateContext,
        /// Zig field names seen at the top level (comptime strings; no copies).
        present: std.ArrayList([]const u8),
        // serval-ee8
        /// Top-level unknown fields gathered under .collect.
        unknown: std.ArrayList(core.FieldValue) = .empty,
        // serval-54c
        /// Projection mode: struct decode early-exits once every field of
        /// the target is seen; the rest of the container is never parsed.
        projection: bool = false,
    };
}

fn decodeTop(comptime T: type, d: anytype) core.DecodeError!T {
    if (@typeInfo(T) == .@"struct" and !comptime core.isMap(T)) return decodeStruct(T, d, true);
    return decodeAny(T, d, .{});
}

// serval-vw4: type-level policies (bytes_policy, enum_tagging) come from the
// enclosing struct's options and flow down through optionals and slices.
fn decodeAny(
    comptime T: type,
    d: anytype,
    comptime parent: core.TypeOptions,
) core.DecodeError!T {
    switch (@typeInfo(T)) {
        // serval-4tr: scalar branches accept coerced inputs per
        // DecodeOptions.coercion (see validate/coercion.zig for the matrix).
        .bool => {
            const tok = try nextToken(d);
            switch (tok) {
                .true => return true,
                .false => return false,
                .string, .allocated_string => |s| {
                    if (d.options.coercion == .none) return error.UnexpectedToken;
                    return validate.coercion.boolFromString(s) orelse error.UnexpectedToken;
                },
                .number, .allocated_number => |s| {
                    if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                    const n = std.fmt.parseInt(i128, s, 10) catch return error.UnexpectedToken;
                    return validate.coercion.boolFromInt(n) orelse error.UnexpectedToken;
                },
                else => return error.UnexpectedToken,
            }
        },
        .int => {
            const tok = try nextToken(d);
            switch (tok) {
                .number, .allocated_number => |s| {
                    if (std.fmt.parseInt(T, s, 10)) |n| return n else |e| switch (e) {
                        error.Overflow => return error.Overflow,
                        error.InvalidCharacter => {
                            // non-integer number: a type mismatch unless
                            // aggressive truncation is on
                            if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                            const f = std.fmt.parseFloat(f64, s) catch return error.InvalidSyntax;
                            return validate.coercion.intFromFloat(T, f) orelse error.Overflow;
                        },
                    }
                },
                .string, .allocated_string => |s| {
                    if (d.options.coercion == .none) return error.UnexpectedToken;
                    return validate.coercion.intFromString(T, s) orelse error.UnexpectedToken;
                },
                .true, .false => {
                    if (d.options.coercion != .aggressive) return error.UnexpectedToken;
                    return if (tok == .true) 1 else 0;
                },
                else => return error.UnexpectedToken,
            }
        },
        .float => {
            const tok = try nextToken(d);
            switch (tok) {
                .number, .allocated_number => |s| return std.fmt.parseFloat(T, s) catch error.InvalidSyntax,
                .string, .allocated_string => |s| {
                    if (d.options.coercion == .none) return error.UnexpectedToken;
                    return validate.coercion.floatFromString(T, s) orelse error.UnexpectedToken;
                },
                else => return error.UnexpectedToken,
            }
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
                return try stringValue(d);
            return try decodeSlice(p.child, d, parent);
        },
        .@"struct" => {
            // serval-2si
            if (comptime core.isMap(T)) return decodeMap(T, d, parent);
            return decodeStruct(T, d, false);
        },
        // serval-x9g
        .@"union" => return decodeUnion(T, d),
        else => @compileError("serval-json: unsupported type " ++ @typeName(T)),
    }
}

// serval-x9g
fn decodeUnion(comptime T: type, d: anytype) core.DecodeError!T {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval-json: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    return switch (comptime opts.union_tagging) {
        .external => decodeUnionExternal(T, d, opts),
        .adjacent => decodeUnionAdjacent(T, d, opts),
        // serval-plc: tag position isn't known up front — buffer the value
        // tree, then map it. Arena recommended (buffered containers become
        // garbage after mapping).
        .internal, .untagged => blk: {
            const buffered = try decodeValue(d);
            // serval-4tr
            break :blk codec.decode.fromValueCoerce(T, d.allocator, buffered, d.options.coercion);
        },
    };
}

// serval-x9g
fn decodeUnionExternal(
    comptime T: type,
    d: anytype,
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
    d: anytype,
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

fn decodeStruct(comptime T: type, d: anytype, comptime is_top: bool) core.DecodeError!T {
    switch (try nextToken(d)) {
        .object_begin => {},
        else => return error.UnexpectedToken,
    }
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;
    var seen = [_]bool{false} ** struct_fields.len;
    // serval-54c
    var seen_count: usize = 0;

    key_loop: while (true) {
        const key = switch (try nextToken(d)) {
            .object_end => break,
            .string, .allocated_string => |s| s,
            else => return error.UnexpectedToken,
        };
        inline for (S.fields, struct_fields, 0..) |sf, zf, i| {
            if (std.mem.eql(u8, key, sf.wire_name)) {
                // serval-sru: nested shape issues get full paths; gated so
                // flat decodes stay allocation-free.
                const descends = comptime core.type_info.containsStruct(zf.type);
                if (descends) d.ctx.pushPath(.{ .field = zf.name });
                @field(result, zf.name) = try decodeAny(zf.type, d, S.options);
                if (descends) d.ctx.popPath();
                // serval-au2
                try validate.coercion.applyStringTransforms(sf.meta, zf.type, &@field(result, zf.name), d.allocator);
                // serval-54c
                if (!seen[i]) seen_count += 1;
                seen[i] = true;
                // serval-0mq: presence only feeds validation — skip the
                // allocation entirely when validation is off.
                if (is_top and d.options.validation != .none) {
                    d.present.append(d.allocator, zf.name) catch return error.OutOfMemory;
                }
                // serval-54c: projection — all fields of P seen, abandon
                // the rest of the container unparsed.
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
                d.scanner.skipValue() catch |e| return mapScanError(e);
            },
            // serval-ee8: collected at the top level only — typed nested
            // structs have no slot to carry unknowns.
            .collect => if (is_top) {
                const owned_key = if (d.options.memory == .owned)
                    d.allocator.dupe(u8, key) catch return error.OutOfMemory
                else
                    key;
                const val = try decodeValue(d);
                d.unknown.append(d.allocator, .{
                    .name = owned_key,
                    .value = val,
                }) catch return error.OutOfMemory;
            } else {
                d.scanner.skipValue() catch |e| return mapScanError(e);
            },
            .ignore => d.scanner.skipValue() catch |e| return mapScanError(e),
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

// serval-ee8
/// Dynamic decode into the format-neutral core.Value. Used for collected
/// unknown fields; also the future home of internal/untagged union tagging.
fn decodeValue(d: anytype) core.DecodeError!core.Value {
    switch (try peek(d)) {
        .true => {
            _ = try nextToken(d);
            return .{ .bool = true };
        },
        .false => {
            _ = try nextToken(d);
            return .{ .bool = false };
        },
        .null => {
            _ = try nextToken(d);
            return .null;
        },
        .string => return .{ .string = try stringSlice(d, true) },
        .number => {
            const s = try numberSlice(d);
            // serval-dfo (D1)
            if (std.fmt.parseInt(i128, s, 10)) |n| return .{ .int = n } else |_| {}
            const f = std.fmt.parseFloat(f64, s) catch return error.InvalidSyntax;
            return .{ .float = f };
        },
        .array_begin => {
            _ = try nextToken(d);
            var items: std.ArrayList(core.Value) = .empty;
            defer items.deinit(d.allocator);
            while (try peek(d) != .array_end) {
                const v = try decodeValue(d);
                items.append(d.allocator, v) catch return error.OutOfMemory;
            }
            _ = try nextToken(d);
            return .{ .array = items.toOwnedSlice(d.allocator) catch return error.OutOfMemory };
        },
        .object_begin => {
            _ = try nextToken(d);
            var fields: std.ArrayList(core.FieldValue) = .empty;
            defer fields.deinit(d.allocator);
            while (true) {
                const key = switch (try nextToken(d)) {
                    .object_end => break,
                    .string, .allocated_string => |s| if (d.options.memory == .owned)
                        d.allocator.dupe(u8, s) catch return error.OutOfMemory
                    else
                        s,
                    else => return error.UnexpectedToken,
                };
                const v = try decodeValue(d);
                fields.append(d.allocator, .{ .name = key, .value = v }) catch
                    return error.OutOfMemory;
            }
            return .{ .object = fields.toOwnedSlice(d.allocator) catch return error.OutOfMemory };
        },
        else => return error.UnexpectedToken,
    }
}

// serval-2si
fn decodeMap(
    comptime M: type,
    d: anytype,
    comptime parent: core.TypeOptions,
) core.DecodeError!M {
    switch (try nextToken(d)) {
        .object_begin => {},
        else => return error.UnexpectedToken,
    }
    var list: std.ArrayList(M.Entry) = .empty;
    defer list.deinit(d.allocator);
    while (true) {
        const key = switch (try nextToken(d)) {
            .object_end => break,
            .string => |s| if (d.options.memory == .owned)
                d.allocator.dupe(u8, s) catch return error.OutOfMemory
            else
                s,
            .allocated_string => |s| s,
            else => return error.UnexpectedToken,
        };
        const descends = comptime core.type_info.containsStruct(M.ValueType);
        if (descends) d.ctx.pushPath(.{ .key = key });
        const v = try decodeAny(M.ValueType, d, parent);
        if (descends) d.ctx.popPath();
        list.append(d.allocator, .{ .key = key, .value = v }) catch return error.OutOfMemory;
    }
    return .{ .entries = list.toOwnedSlice(d.allocator) catch return error.OutOfMemory };
}

fn decodeSlice(
    comptime Child: type,
    d: anytype,
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

fn nextToken(d: anytype) core.DecodeError!std.json.Token {
    return d.scanner.nextAlloc(d.allocator, .alloc_if_needed) catch |e| mapScanError(e);
}

fn peek(d: anytype) core.DecodeError!std.json.TokenType {
    return d.scanner.peekNextTokenType() catch |e| mapScanError(e);
}

fn numberSlice(d: anytype) core.DecodeError![]const u8 {
    return switch (try nextToken(d)) {
        .number, .allocated_number => |s| s,
        else => error.UnexpectedToken,
    };
}

// serval-4tr
/// String-typed field value: a string token, or under aggressive coercion
/// a number's token text or a bool literal.
fn stringValue(d: anytype) core.DecodeError![]const u8 {
    const tok = try nextToken(d);
    switch (tok) {
        .string => |s| return if (d.options.memory == .owned)
            d.allocator.dupe(u8, s) catch error.OutOfMemory
        else
            s,
        .allocated_string => |s| return s,
        .number => |s| {
            if (d.options.coercion != .aggressive) return error.UnexpectedToken;
            return if (d.options.memory == .owned)
                d.allocator.dupe(u8, s) catch error.OutOfMemory
            else
                s;
        },
        .allocated_number => |s| {
            if (d.options.coercion != .aggressive) return error.UnexpectedToken;
            return s;
        },
        .true, .false => {
            if (d.options.coercion != .aggressive) return error.UnexpectedToken;
            return if (tok == .true) "true" else "false";
        },
        else => return error.UnexpectedToken,
    }
}

/// `dupe_for_owned`: with MemoryMode.owned, unescaped string tokens (which
/// borrow from the input buffer) are duplicated so the result outlives it.
fn stringSlice(d: anytype, dupe_for_owned: bool) core.DecodeError![]const u8 {
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
        // serval-x09
        error.ReadFailed => error.ReadFailed,
        else => error.InvalidSyntax,
    };
}
