// serval-bfi
//! Schema-driven MessagePack encode: minimal-width int encodings, str/bin
//! split via bytes_policy, wire names from rename metadata, all four union
//! tagging modes.

const std = @import("std");
const core = @import("serval-core");
const codec = @import("serval-codec");

const Writer = std.Io.Writer;

/// Encode `value` to an owned msgpack buffer. Caller frees with `allocator`.
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
        .bool => try w.writeByte(if (v) 0xc3 else 0xc2),
        .int, .comptime_int => try writeInt(w, v),
        .float, .comptime_float => try writeFloat(w, v),
        .optional => |o| {
            if (v) |payload| {
                try encodeAny(o.child, payload, w, parent);
            } else {
                try w.writeByte(0xc0);
            }
        },
        .@"enum" => switch (parent.enum_tagging) {
            .name => try writeStr(w, @tagName(v)),
            .value => try writeInt(w, @intFromEnum(v)),
        },
        .pointer => |p| {
            if (p.size != .slice)
                @compileError("serval-msgpack: unsupported pointer type " ++ @typeName(T));
            if (p.child == u8 and parent.bytes_policy == .string) {
                try writeStr(w, v);
            } else if (p.child == u8) {
                try writeBin(w, v);
            } else {
                try writeArrayHeader(w, v.len);
                for (v) |item| try encodeAny(p.child, item, w, parent);
            }
        },
        .@"struct" => try encodeStruct(T, v, w),
        .@"union" => try encodeUnion(T, v, w),
        else => @compileError("serval-msgpack: unsupported type " ++ @typeName(T)),
    }
}

fn encodeStruct(comptime T: type, v: T, w: *Writer) Writer.Error!void {
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    try writeMapHeader(w, struct_fields.len);
    inline for (S.fields, struct_fields) |sf, zf| {
        try writeStr(w, sf.wire_name);
        try encodeAny(zf.type, @field(v, zf.name), w, S.options);
    }
}

fn encodeUnion(comptime T: type, v: T, w: *Writer) Writer.Error!void {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval-msgpack: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    switch (comptime opts.union_tagging) {
        .external => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                if (@TypeOf(payload) == void) {
                    try writeStr(w, wire);
                } else {
                    try writeMapHeader(w, 1);
                    try writeStr(w, wire);
                    try encodeAny(@TypeOf(payload), payload, w, .{});
                }
            },
        },
        .adjacent => switch (v) {
            inline else => |payload, tag| {
                const wire = comptime core.naming.convert(opts.rename_all, @tagName(tag));
                const has_content = @TypeOf(payload) != void;
                try writeMapHeader(w, if (has_content) 2 else 1);
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
                    try writeMapHeader(w, 1);
                    try writeStr(w, opts.union_tag_field);
                    try writeStr(w, wire);
                } else {
                    if (@typeInfo(P) != .@"struct")
                        @compileError("serval-msgpack: internal union tagging requires struct or void payloads: " ++ @typeName(T));
                    const PS = core.schemaOf(P);
                    const pfields = @typeInfo(P).@"struct".fields;
                    try writeMapHeader(w, 1 + pfields.len);
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
                    try w.writeByte(0xc0);
                } else {
                    try encodeAny(@TypeOf(payload), payload, w, .{});
                }
            },
        },
    }
}

fn writeInt(w: *Writer, v: anytype) Writer.Error!void {
    if (@bitSizeOf(@TypeOf(v)) > 64 and @TypeOf(v) != comptime_int)
        @compileError("serval-msgpack: ints wider than 64 bits unsupported");
    const x: i128 = v;
    if (x >= 0) {
        if (x <= 0x7f) {
            try w.writeByte(@intCast(x));
        } else if (x <= std.math.maxInt(u8)) {
            try w.writeByte(0xcc);
            try writeBig(w, u8, @intCast(x));
        } else if (x <= std.math.maxInt(u16)) {
            try w.writeByte(0xcd);
            try writeBig(w, u16, @intCast(x));
        } else if (x <= std.math.maxInt(u32)) {
            try w.writeByte(0xce);
            try writeBig(w, u32, @intCast(x));
        } else {
            try w.writeByte(0xcf);
            try writeBig(w, u64, @intCast(x));
        }
    } else {
        if (x >= -32) {
            try w.writeByte(@bitCast(@as(i8, @intCast(x))));
        } else if (x >= std.math.minInt(i8)) {
            try w.writeByte(0xd0);
            try writeBig(w, u8, @bitCast(@as(i8, @intCast(x))));
        } else if (x >= std.math.minInt(i16)) {
            try w.writeByte(0xd1);
            try writeBig(w, u16, @bitCast(@as(i16, @intCast(x))));
        } else if (x >= std.math.minInt(i32)) {
            try w.writeByte(0xd2);
            try writeBig(w, u32, @bitCast(@as(i32, @intCast(x))));
        } else {
            try w.writeByte(0xd3);
            try writeBig(w, u64, @bitCast(@as(i64, @intCast(x))));
        }
    }
}

fn writeFloat(w: *Writer, v: anytype) Writer.Error!void {
    if (@TypeOf(v) == f32) {
        try w.writeByte(0xca);
        try writeBig(w, u32, @bitCast(v));
    } else {
        try w.writeByte(0xcb);
        try writeBig(w, u64, @bitCast(@as(f64, v)));
    }
}

fn writeStr(w: *Writer, s: []const u8) Writer.Error!void {
    if (s.len <= 31) {
        try w.writeByte(0xa0 | @as(u8, @intCast(s.len)));
    } else if (s.len <= std.math.maxInt(u8)) {
        try w.writeByte(0xd9);
        try writeBig(w, u8, @intCast(s.len));
    } else if (s.len <= std.math.maxInt(u16)) {
        try w.writeByte(0xda);
        try writeBig(w, u16, @intCast(s.len));
    } else {
        try w.writeByte(0xdb);
        try writeBig(w, u32, @intCast(s.len));
    }
    try w.writeAll(s);
}

fn writeBin(w: *Writer, s: []const u8) Writer.Error!void {
    if (s.len <= std.math.maxInt(u8)) {
        try w.writeByte(0xc4);
        try writeBig(w, u8, @intCast(s.len));
    } else if (s.len <= std.math.maxInt(u16)) {
        try w.writeByte(0xc5);
        try writeBig(w, u16, @intCast(s.len));
    } else {
        try w.writeByte(0xc6);
        try writeBig(w, u32, @intCast(s.len));
    }
    try w.writeAll(s);
}

fn writeArrayHeader(w: *Writer, n: usize) Writer.Error!void {
    if (n <= 15) {
        try w.writeByte(0x90 | @as(u8, @intCast(n)));
    } else if (n <= std.math.maxInt(u16)) {
        try w.writeByte(0xdc);
        try writeBig(w, u16, @intCast(n));
    } else {
        try w.writeByte(0xdd);
        try writeBig(w, u32, @intCast(n));
    }
}

fn writeMapHeader(w: *Writer, n: usize) Writer.Error!void {
    if (n <= 15) {
        try w.writeByte(0x80 | @as(u8, @intCast(n)));
    } else if (n <= std.math.maxInt(u16)) {
        try w.writeByte(0xde);
        try writeBig(w, u16, @intCast(n));
    } else {
        try w.writeByte(0xdf);
        try writeBig(w, u32, @intCast(n));
    }
}

fn writeBig(w: *Writer, comptime U: type, v: U) Writer.Error!void {
    var buf: [@divExact(@bitSizeOf(U), 8)]u8 = undefined;
    std.mem.writeInt(U, &buf, v, .big);
    try w.writeAll(&buf);
}
