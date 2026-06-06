// serval-vw4
//! Schema-driven JSON encode: wire names from rename metadata, bytes_policy
//! ([]const u8 as string vs number array), enum_tagging (name vs value),
//! and pretty printing.
//!
//! Type-level policies (bytes_policy, enum_tagging) come from the enclosing
//! struct's `pub const serval` metadata and flow down through optionals and
//! slices; nested structs switch to their own options.

const std = @import("std");
const core = @import("serval-core");
const codec = @import("serval-codec");

/// Encode `value` to an owned JSON string. Caller frees with `allocator`.
pub fn encodeAlloc(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: T,
    options: codec.EncodeOptions,
) error{OutOfMemory}![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    encodeToWriter(T, value, options, &aw.writer) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
}

// serval-x09
/// Encode `value` directly to a std.Io.Writer.
pub fn encodeToWriter(
    comptime T: type,
    value: T,
    options: codec.EncodeOptions,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    var enc = Encoder{ .writer = writer, .options = options };
    try encodeAny(T, value, &enc, .{});
}

// serval-x09
/// Exact encoded length without producing output.
pub fn measureEncodedLen(
    comptime T: type,
    value: T,
    options: codec.EncodeOptions,
) usize {
    var counter: std.Io.Writer.Discarding = .init(&.{});
    // A discarding writer cannot fail.
    encodeToWriter(T, value, options, &counter.writer) catch unreachable;
    return @intCast(counter.count + counter.writer.end);
}

const Encoder = struct {
    writer: *std.Io.Writer,
    options: codec.EncodeOptions,
    depth: usize = 0,
};

const WriteError = std.Io.Writer.Error;

fn encodeAny(
    comptime T: type,
    v: T,
    e: *Encoder,
    comptime parent: core.TypeOptions,
) WriteError!void {
    switch (@typeInfo(T)) {
        .bool => try e.writer.writeAll(if (v) "true" else "false"),
        .int, .comptime_int => try e.writer.print("{d}", .{v}),
        .float, .comptime_float => try e.writer.print("{d}", .{v}),
        .optional => |o| {
            if (v) |payload| {
                try encodeAny(o.child, payload, e, parent);
            } else {
                try e.writer.writeAll("null");
            }
        },
        .@"enum" => switch (parent.enum_tagging) {
            .name => try std.json.Stringify.encodeJsonString(@tagName(v), .{}, e.writer),
            .value => try e.writer.print("{d}", .{@intFromEnum(v)}),
        },
        .pointer => |p| {
            if (p.size != .slice)
                @compileError("serval-json: unsupported pointer type " ++ @typeName(T));
            if (p.child == u8 and parent.bytes_policy == .string) {
                try std.json.Stringify.encodeJsonString(v, .{}, e.writer);
            } else {
                try encodeArray(p.child, v, e, parent);
            }
        },
        .@"struct" => try encodeStruct(T, v, e),
        // serval-x9g
        .@"union" => try encodeUnion(T, v, e),
        else => @compileError("serval-json: unsupported type " ++ @typeName(T)),
    }
}

fn encodeStruct(comptime T: type, v: T, e: *Encoder) WriteError!void {
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    try e.writer.writeByte('{');
    e.depth += 1;
    inline for (S.fields, struct_fields, 0..) |sf, zf, i| {
        if (i != 0) try e.writer.writeByte(',');
        try newlineIndent(e);
        try fieldKey(sf.wire_name, e);
        try encodeAny(zf.type, @field(v, zf.name), e, S.options);
    }
    e.depth -= 1;
    if (struct_fields.len != 0) try newlineIndent(e);
    try e.writer.writeByte('}');
}

fn encodeArray(
    comptime Child: type,
    items: []const Child,
    e: *Encoder,
    comptime parent: core.TypeOptions,
) WriteError!void {
    try e.writer.writeByte('[');
    e.depth += 1;
    for (items, 0..) |item, i| {
        if (i != 0) try e.writer.writeByte(',');
        try newlineIndent(e);
        try encodeAny(Child, item, e, parent);
    }
    e.depth -= 1;
    if (items.len != 0) try newlineIndent(e);
    try e.writer.writeByte(']');
}

// serval-x9g
fn encodeUnion(comptime T: type, v: T, e: *Encoder) WriteError!void {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval-json: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    switch (comptime opts.union_tagging) {
        .external => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                if (@TypeOf(payload) == void) {
                    // unit variant: bare string
                    try std.json.Stringify.encodeJsonString(wire, .{}, e.writer);
                } else {
                    try e.writer.writeByte('{');
                    e.depth += 1;
                    try newlineIndent(e);
                    try fieldKey(wire, e);
                    try encodeAny(@TypeOf(payload), payload, e, .{});
                    e.depth -= 1;
                    try newlineIndent(e);
                    try e.writer.writeByte('}');
                }
            },
        },
        .adjacent => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                try e.writer.writeByte('{');
                e.depth += 1;
                try newlineIndent(e);
                try fieldKey(opts.union_tag_field, e);
                try std.json.Stringify.encodeJsonString(wire, .{}, e.writer);
                if (@TypeOf(payload) != void) {
                    try e.writer.writeByte(',');
                    try newlineIndent(e);
                    try fieldKey(opts.union_content_field, e);
                    try encodeAny(@TypeOf(payload), payload, e, .{});
                }
                e.depth -= 1;
                try newlineIndent(e);
                try e.writer.writeByte('}');
            },
        },
        // serval-plc
        .internal => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                const P = @TypeOf(payload);
                try e.writer.writeByte('{');
                e.depth += 1;
                try newlineIndent(e);
                try fieldKey(opts.union_tag_field, e);
                try std.json.Stringify.encodeJsonString(wire, .{}, e.writer);
                if (P != void) {
                    if (@typeInfo(P) != .@"struct")
                        @compileError("serval-json: internal union tagging requires struct or void payloads: " ++ @typeName(T));
                    const PS = core.schemaOf(P);
                    const pfields = @typeInfo(P).@"struct".fields;
                    inline for (PS.fields, pfields) |sf, zf| {
                        try e.writer.writeByte(',');
                        try newlineIndent(e);
                        try fieldKey(sf.wire_name, e);
                        try encodeAny(zf.type, @field(payload, zf.name), e, PS.options);
                    }
                }
                e.depth -= 1;
                try newlineIndent(e);
                try e.writer.writeByte('}');
            },
        },
        // serval-plc: payload encodes bare; unit variants carry no
        // information and encode as null.
        .untagged => switch (v) {
            inline else => |payload| {
                if (@TypeOf(payload) == void) {
                    try e.writer.writeAll("null");
                } else {
                    try encodeAny(@TypeOf(payload), payload, e, .{});
                }
            },
        },
    }
}

// serval-x9g
fn fieldKey(key: []const u8, e: *Encoder) WriteError!void {
    try std.json.Stringify.encodeJsonString(key, .{}, e.writer);
    try e.writer.writeByte(':');
    if (e.options.pretty) try e.writer.writeByte(' ');
}

fn newlineIndent(e: *Encoder) WriteError!void {
    if (!e.options.pretty) return;
    try e.writer.writeByte('\n');
    try e.writer.splatByteAll(' ', e.depth * 2);
}
