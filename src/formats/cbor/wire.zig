// serval-2wi
//! CBOR (RFC 8949) wire layer for codec.binary.Backend. Definite lengths
//! only (indefinite items rejected); tags (major type 6) rejected; f16
//! decoded but never emitted.

const std = @import("std");
const codec = @import("serval-codec");
const core = @import("serval-core");

const Header = codec.binary.Header;
const Writer = std.Io.Writer;

/// Major 7, simple value 22.
pub const null_byte: u8 = 0xf6;

// serval-sj2: RFC 8949 §4.2.1 — bytewise order of encoded keys is
// length-first for definite text strings.
pub const canonical_key_order: codec.KeyOrder = .length_first;

/// Argument value for a major type (RFC 8949 §3). Rejects reserved
/// additional-info values 28-30 and indefinite lengths (31).
fn readArg(d: anytype, ai: u5) core.DecodeError!u64 {
    return switch (ai) {
        0...23 => ai,
        24 => try d.readBig(u8),
        25 => try d.readBig(u16),
        26 => try d.readBig(u32),
        27 => try d.readBig(u64),
        else => error.UnexpectedToken,
    };
}

fn readLen(d: anytype, ai: u5) core.DecodeError!usize {
    return std.math.cast(usize, try readArg(d, ai)) orelse error.Overflow;
}

pub fn readHeader(d: anytype) core.DecodeError!Header {
    const b = try d.readByte();
    const major: u3 = @intCast(b >> 5);
    const ai: u5 = @intCast(b & 0x1f);
    return switch (major) {
        0 => .{ .int = try readArg(d, ai) },
        1 => .{ .int = -1 - @as(i128, try readArg(d, ai)) },
        2 => .{ .bin = try readLen(d, ai) },
        3 => .{ .str = try readLen(d, ai) },
        4 => .{ .array = try readLen(d, ai) },
        5 => .{ .map = try readLen(d, ai) },
        // tags (major type 6) unsupported in v1
        6 => error.UnexpectedToken,
        7 => switch (ai) {
            20 => .{ .bool = false },
            21 => .{ .bool = true },
            22 => .nil,
            25 => .{ .float = @as(f16, @bitCast(try d.readBig(u16))) },
            26 => .{ .float = @as(f32, @bitCast(try d.readBig(u32))) },
            27 => .{ .float = @as(f64, @bitCast(try d.readBig(u64))) },
            // other simple values (incl. undefined) rejected
            else => error.UnexpectedToken,
        },
    };
}

pub fn writeNull(w: *Writer) Writer.Error!void {
    try w.writeByte(0xf6);
}

pub fn writeBool(w: *Writer, v: bool) Writer.Error!void {
    try w.writeByte(if (v) 0xf5 else 0xf4);
}

pub fn writeInt(w: *Writer, v: anytype) Writer.Error!void {
    if (@bitSizeOf(@TypeOf(v)) > 64 and @TypeOf(v) != comptime_int)
        @compileError("serval-cbor: ints wider than 64 bits unsupported");
    const x: i128 = v;
    if (x >= 0) {
        try writeTypeArg(w, 0, @intCast(x));
    } else {
        try writeTypeArg(w, 1, @intCast(-1 - x));
    }
}

pub fn writeFloat(w: *Writer, v: anytype) Writer.Error!void {
    if (@TypeOf(v) == f32) {
        try w.writeByte(0xfa);
        try writeBig(w, u32, @bitCast(v));
    } else {
        try w.writeByte(0xfb);
        try writeBig(w, u64, @bitCast(@as(f64, v)));
    }
}

pub fn writeStr(w: *Writer, s: []const u8) Writer.Error!void {
    try writeTypeArg(w, 3, s.len);
    try w.writeAll(s);
}

pub fn writeBin(w: *Writer, s: []const u8) Writer.Error!void {
    try writeTypeArg(w, 2, s.len);
    try w.writeAll(s);
}

pub fn writeArrayHeader(w: *Writer, n: usize) Writer.Error!void {
    try writeTypeArg(w, 4, n);
}

pub fn writeMapHeader(w: *Writer, n: usize) Writer.Error!void {
    try writeTypeArg(w, 5, n);
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

fn writeBig(w: *Writer, comptime U: type, v: U) Writer.Error!void {
    var buf: [@divExact(@bitSizeOf(U), 8)]u8 = undefined;
    std.mem.writeInt(U, &buf, v, .big);
    try w.writeAll(&buf);
}
