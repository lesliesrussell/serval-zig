// serval-2wi
//! MessagePack wire layer for codec.binary.Backend: header classification
//! and minimal-width scalar/container writers. Ext types unsupported.

const std = @import("std");
const codec = @import("serval-codec");
const core = @import("serval-core");

const Header = codec.binary.Header;
const Writer = std.Io.Writer;

pub const null_byte: u8 = 0xc0;

// serval-sj2
pub const canonical_key_order: codec.KeyOrder = .lexicographic;

pub fn readHeader(d: anytype) core.DecodeError!Header {
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
        // serval-8kr: ext family — payload as bytes under .skip
        0xd4...0xd8 => extAsBin(d, @as(usize, 1) << @intCast(b - 0xd4)),
        0xc7 => extAsBin(d, try d.readBig(u8)),
        0xc8 => extAsBin(d, try d.readBig(u16)),
        0xc9 => extAsBin(d, try d.readBig(u32)),
        // 0xc1 is never used
        else => error.UnexpectedToken,
    };
}

// serval-8kr
fn extAsBin(d: anytype, len: usize) core.DecodeError!Header {
    if (d.options.extensions == .reject) return error.UnexpectedToken;
    _ = try d.readByte(); // ext type discarded
    return .{ .bin = len };
}

pub fn writeNull(w: *Writer) Writer.Error!void {
    try w.writeByte(0xc0);
}

pub fn writeBool(w: *Writer, v: bool) Writer.Error!void {
    try w.writeByte(if (v) 0xc3 else 0xc2);
}

pub fn writeInt(w: *Writer, v: anytype) Writer.Error!void {
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

pub fn writeFloat(w: *Writer, v: anytype) Writer.Error!void {
    if (@TypeOf(v) == f32) {
        try w.writeByte(0xca);
        try writeBig(w, u32, @bitCast(v));
    } else {
        try w.writeByte(0xcb);
        try writeBig(w, u64, @bitCast(@as(f64, v)));
    }
}

pub fn writeStr(w: *Writer, s: []const u8) Writer.Error!void {
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

pub fn writeBin(w: *Writer, s: []const u8) Writer.Error!void {
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

pub fn writeArrayHeader(w: *Writer, n: usize) Writer.Error!void {
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

pub fn writeMapHeader(w: *Writer, n: usize) Writer.Error!void {
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
