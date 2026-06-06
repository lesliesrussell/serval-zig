// serval-9kw
//! ZON encode via std.zon serializer.

const std = @import("std");
const codec = @import("serval-codec");

/// Encode `value` to an owned ZON string. Caller frees with `allocator`.
/// EncodeOptions.pretty maps to standard Zig whitespace style.
pub fn encodeAlloc(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: T,
    options: codec.EncodeOptions,
) error{OutOfMemory}![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    std.zon.stringify.serialize(value, .{
        .whitespace = options.pretty,
    }, &aw.writer) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
}
