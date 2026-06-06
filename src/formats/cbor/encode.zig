// serval-7jg
//! Schema-driven CBOR (RFC 8949) encode: minimal-width type arguments,
//! text vs byte strings via bytes_policy, wire names from rename metadata,
//! all four union tagging modes. Definite lengths only; no tags.

const std = @import("std");
const core = @import("serval-core");
const codec = @import("serval-codec");

const Writer = std.Io.Writer;

/// Encode `value` to an owned CBOR buffer. Caller frees with `allocator`.
pub fn encodeAlloc(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: T,
    options: codec.EncodeOptions,
) error{OutOfMemory}![]u8 {
    var aw: Writer.Allocating = .init(allocator);
    defer aw.deinit();
    encodeToWriter(T, value, options, &aw.writer) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
}

/// Encode `value` directly to a std.Io.Writer. EncodeOptions.pretty is
/// meaningless for a binary format and ignored.
pub fn encodeToWriter(
    comptime T: type,
    value: T,
    options: codec.EncodeOptions,
    writer: *Writer,
) Writer.Error!void {
    _ = options;
    try encodeAny(T, value, writer, .{});
}

/// Exact encoded length without producing output.
pub fn measureEncodedLen(
    comptime T: type,
    value: T,
    options: codec.EncodeOptions,
) usize {
    var counter: Writer.Discarding = .init(&.{});
    encodeToWriter(T, value, options, &counter.writer) catch unreachable;
    return @intCast(counter.count + counter.writer.end);
}

fn encodeAny(
    comptime T: type,
    v: T,
    w: *Writer,
    comptime parent: core.TypeOptions,
) Writer.Error!void {
    switch (@typeInfo(T)) {
        .bool => try w.writeByte(if (v) 0xf5 else 0xf4),
        .int, .comptime_int => try writeInt(w, v),
        .float, .comptime_float => try writeFloat(w, v),
        .optional => |o| {
            if (v) |payload| {
                try encodeAny(o.child, payload, w, parent);
            } else {
                try w.writeByte(0xf6); // null
            }
        },
        .@"enum" => switch (parent.enum_tagging) {
            .name => try writeStr(w, @tagName(v)),
            .value => try writeInt(w, @intFromEnum(v)),
        },
        .pointer => |p| {
            if (p.size != .slice)
                @compileError("serval-cbor: unsupported pointer type " ++ @typeName(T));
            if (p.child == u8 and parent.bytes_policy == .string) {
                try writeStr(w, v);
            } else if (p.child == u8) {
                try writeTypeArg(w, 2, v.len); // byte string
                try w.writeAll(v);
            } else {
                try writeTypeArg(w, 4, v.len); // array
                for (v) |item| try encodeAny(p.child, item, w, parent);
            }
        },
        .@"struct" => try encodeStruct(T, v, w),
        .@"union" => try encodeUnion(T, v, w),
        else => @compileError("serval-cbor: unsupported type " ++ @typeName(T)),
    }
}

fn encodeStruct(comptime T: type, v: T, w: *Writer) Writer.Error!void {
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    try writeTypeArg(w, 5, struct_fields.len); // map
    inline for (S.fields, struct_fields) |sf, zf| {
        try writeStr(w, sf.wire_name);
        try encodeAny(zf.type, @field(v, zf.name), w, S.options);
    }
}

fn encodeUnion(comptime T: type, v: T, w: *Writer) Writer.Error!void {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval-cbor: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    switch (comptime opts.union_tagging) {
        .external => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                if (@TypeOf(payload) == void) {
                    try writeStr(w, wire);
                } else {
                    try writeTypeArg(w, 5, 1);
                    try writeStr(w, wire);
                    try encodeAny(@TypeOf(payload), payload, w, .{});
                }
            },
        },
        .adjacent => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                const has_content = @TypeOf(payload) != void;
                try writeTypeArg(w, 5, if (has_content) 2 else 1);
                try writeStr(w, opts.union_tag_field);
                try writeStr(w, wire);
                if (has_content) {
                    try writeStr(w, opts.union_content_field);
                    try encodeAny(@TypeOf(payload), payload, w, .{});
                }
            },
        },
        .internal => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                const P = @TypeOf(payload);
                if (P == void) {
                    try writeTypeArg(w, 5, 1);
                    try writeStr(w, opts.union_tag_field);
                    try writeStr(w, wire);
                } else {
                    if (@typeInfo(P) != .@"struct")
                        @compileError("serval-cbor: internal union tagging requires struct or void payloads: " ++ @typeName(T));
                    const PS = core.schemaOf(P);
                    const pfields = @typeInfo(P).@"struct".fields;
                    try writeTypeArg(w, 5, 1 + pfields.len);
                    try writeStr(w, opts.union_tag_field);
                    try writeStr(w, wire);
                    inline for (PS.fields, pfields) |sf, zf| {
                        try writeStr(w, sf.wire_name);
                        try encodeAny(zf.type, @field(payload, zf.name), w, PS.options);
                    }
                }
            },
        },
        .untagged => switch (v) {
            inline else => |payload| {
                if (@TypeOf(payload) == void) {
                    try w.writeByte(0xf6);
                } else {
                    try encodeAny(@TypeOf(payload), payload, w, .{});
                }
            },
        },
    }
}

/// Major type + minimal-width argument (RFC 8949 §3).
fn writeTypeArg(w: *Writer, major: u3, value: u64) Writer.Error!void {
    const mt: u8 = @as(u8, major) << 5;
    if (value < 24) {
        try w.writeByte(mt | @as(u8, @intCast(value)));
    } else if (value <= std.math.maxInt(u8)) {
        try w.writeByte(mt | 24);
        try writeBig(w, u8, @intCast(value));
    } else if (value <= std.math.maxInt(u16)) {
        try w.writeByte(mt | 25);
        try writeBig(w, u16, @intCast(value));
    } else if (value <= std.math.maxInt(u32)) {
        try w.writeByte(mt | 26);
        try writeBig(w, u32, @intCast(value));
    } else {
        try w.writeByte(mt | 27);
        try writeBig(w, u64, value);
    }
}

fn writeInt(w: *Writer, v: anytype) Writer.Error!void {
    if (@bitSizeOf(@TypeOf(v)) > 64 and @TypeOf(v) != comptime_int)
        @compileError("serval-cbor: ints wider than 64 bits unsupported");
    const x: i128 = v;
    if (x >= 0) {
        try writeTypeArg(w, 0, @intCast(x));
    } else {
        try writeTypeArg(w, 1, @intCast(-1 - x));
    }
}

fn writeFloat(w: *Writer, v: anytype) Writer.Error!void {
    if (@TypeOf(v) == f32) {
        try w.writeByte(0xfa);
        try writeBig(w, u32, @bitCast(v));
    } else {
        try w.writeByte(0xfb);
        try writeBig(w, u64, @bitCast(@as(f64, v)));
    }
}

fn writeStr(w: *Writer, s: []const u8) Writer.Error!void {
    try writeTypeArg(w, 3, s.len);
    try w.writeAll(s);
}

fn writeBig(w: *Writer, comptime U: type, v: U) Writer.Error!void {
    var buf: [@divExact(@bitSizeOf(U), 8)]u8 = undefined;
    std.mem.writeInt(U, &buf, v, .big);
    try w.writeAll(&buf);
}
