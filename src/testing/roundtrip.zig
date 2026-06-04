// serval-15q
//! Encode→decode roundtrip assertion helper.

const std = @import("std");
const json = @import("serval-json");

/// Encode `value` to JSON, decode it back, and expect deep equality.
/// Pass an arena allocator; this helper does not free.
pub fn expectRoundtrip(comptime T: type, allocator: std.mem.Allocator, value: T) !void {
    const encoded = try json.encodeAlloc(T, allocator, value, .{});
    const decoded = try json.decode(T, allocator, encoded, .{});
    try std.testing.expectEqualDeep(value, decoded);
}
