// serval-15q
//! Coercion policy, conversion helpers, and string transforms
//! (validation pipeline phase 2).

const std = @import("std");
const core = @import("serval-core");

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
    // serval-dfo (D3): wire data is not Zig source — digit separators
    // ("1_0") are rejected rather than silently parsed.
    if (std.mem.indexOfScalar(u8, s, '_') != null) return null;
    return std.fmt.parseInt(T, s, 10) catch null;
}

// serval-4tr
pub fn floatFromString(comptime T: type, s: []const u8) ?T {
    // serval-dfo (D2/D3): finite decimal only — "inf"/"nan" spellings and
    // digit separators do not coerce.
    if (std.mem.indexOfScalar(u8, s, '_') != null) return null;
    const f = std.fmt.parseFloat(T, s) catch return null;
    if (!std.math.isFinite(f)) return null;
    return f;
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

// serval-au2
/// Apply .trim/.lowercase to a string-typed field value in place.
/// Decode-time only — typed check() and valueAgainstSchema see values
/// as-is. No-op for non-string types and when no transform is set.
pub fn applyStringTransforms(
    comptime meta: core.FieldMeta,
    comptime FT: type,
    value: *FT,
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    if (comptime !(meta.trim or meta.lowercase)) return;
    switch (@typeInfo(FT)) {
        .optional => |o| {
            if (value.*) |payload| {
                var tmp: o.child = payload;
                try applyStringTransforms(meta, o.child, &tmp, allocator);
                value.* = tmp;
            }
        },
        .pointer => |p| {
            if (p.size != .slice or p.child != u8) return;
            value.* = try transformedString(meta, allocator, value.*);
        },
        else => {},
    }
}

// serval-au2
fn transformedString(
    comptime meta: core.FieldMeta,
    allocator: std.mem.Allocator,
    s: []const u8,
) error{OutOfMemory}![]const u8 {
    var out = s;
    if (meta.trim) out = std.mem.trim(u8, out, &std.ascii.whitespace);
    if (meta.lowercase) {
        const buf = try allocator.dupe(u8, out);
        for (buf) |*c| c.* = std.ascii.toLower(c.*);
        out = buf;
    }
    return out;
}
