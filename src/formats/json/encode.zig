// serval-15q
//! JSON encode. Currently bootstrapped on std.json; schema-driven encoding
//! (renames, bytes policy, enum tagging) replaces this internals-first.

const std = @import("std");
const codec = @import("serval-codec");

/// Encode `value` to an owned JSON string. Caller frees with `allocator`.
pub fn encodeAlloc(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: T,
    options: codec.EncodeOptions,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{
        .whitespace = if (options.pretty) .indent_2 else .minified,
    })});
}
