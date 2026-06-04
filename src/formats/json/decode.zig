// serval-15q
//! JSON decode. Currently bootstrapped on std.json (allocations follow the
//! passed allocator — pass an arena for MemoryMode.arena semantics).
//! The schema-driven decoder with borrowed mode, presence tracking, and
//! validation integration replaces this internals-first.

const std = @import("std");
const codec = @import("serval-codec");

/// Decode `input` into a typed T. Result memory is allocated with
/// `allocator`; pass an arena allocator and free it wholesale.
pub fn decode(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) !T {
    return std.json.parseFromSliceLeaky(T, allocator, input, .{
        .ignore_unknown_fields = options.unknown_fields != .reject,
    });
}
