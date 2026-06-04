// serval-15q
//! Allocation strategy helpers for the three memory modes.

const std = @import("std");
const options = @import("options.zig");

/// Resolve the allocator a decode should use for a given memory mode.
/// Reserved: borrowed mode threads a scratch allocator for unavoidable
/// escapes (e.g. strings containing escape sequences).
pub fn allocatorFor(
    mode: options.MemoryMode,
    owned: std.mem.Allocator,
    arena: ?std.mem.Allocator,
) std.mem.Allocator {
    return switch (mode) {
        .owned => owned,
        .arena => arena orelse owned,
        .borrowed => owned,
    };
}
