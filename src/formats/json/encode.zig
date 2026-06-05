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
    var enc = Encoder{ .writer = &aw.writer, .options = options };
    encodeAny(T, value, &enc, .{}) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
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
        // TODO(serval): tagged unions per UnionTagging policy (serval-x9g).
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
        try std.json.Stringify.encodeJsonString(sf.wire_name, .{}, e.writer);
        try e.writer.writeByte(':');
        if (e.options.pretty) try e.writer.writeByte(' ');
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

fn newlineIndent(e: *Encoder) WriteError!void {
    if (!e.options.pretty) return;
    try e.writer.writeByte('\n');
    try e.writer.splatByteAll(' ', e.depth * 2);
}
