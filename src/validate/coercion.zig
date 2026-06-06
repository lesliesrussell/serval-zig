// serval-15q
//! Coercion policy and conversion helpers (validation pipeline phase 2).

const std = @import("std");

pub const CoercionMode = enum {
    /// No conversions; types must match exactly.
    none,
    /// Lossless conversions only: numeric string → int (exact parse),
    /// string → float, exact "true"/"false" → bool.
    safe,
    /// Lossy conversions allowed on top of safe: float → int (truncated
    /// toward zero, range-checked), int 0/1 → bool, bool → int 0/1,
    /// scalar → string.
    aggressive,
};

// serval-4tr
pub fn intFromString(comptime T: type, s: []const u8) ?T {
    return std.fmt.parseInt(T, s, 10) catch null;
}

// serval-4tr
pub fn floatFromString(comptime T: type, s: []const u8) ?T {
    return std.fmt.parseFloat(T, s) catch null;
}

// serval-4tr
pub fn boolFromString(s: []const u8) ?bool {
    if (std.mem.eql(u8, s, "true")) return true;
    if (std.mem.eql(u8, s, "false")) return false;
    return null;
}

// serval-4tr
/// Truncate toward zero; null when non-finite or out of T's range
/// (callers map null to error.Overflow where that distinction matters).
pub fn intFromFloat(comptime T: type, f: f64) ?T {
    const t = @trunc(f);
    if (!std.math.isFinite(t)) return null;
    if (t < @as(f64, @floatFromInt(std.math.minInt(T))) or
        t > @as(f64, @floatFromInt(std.math.maxInt(T)))) return null;
    return @intFromFloat(t);
}

// serval-4tr
/// Only 0 and 1 convert; anything else is a type error, not truthiness.
pub fn boolFromInt(n: i128) ?bool {
    return switch (n) {
        0 => false,
        1 => true,
        else => null,
    };
}
