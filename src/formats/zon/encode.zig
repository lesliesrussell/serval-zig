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
    encodeToWriter(T, value, options, &aw.writer) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
}

// serval-x09
/// Encode `value` directly to a std.Io.Writer.
pub fn encodeToWriter(
    comptime T: type,
    value: T,
    options: codec.EncodeOptions,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try std.zon.stringify.serialize(value, .{
        .whitespace = options.pretty,
    }, writer);
}

// serval-x09
/// Exact encoded length without producing output.
pub fn measureEncodedLen(
    comptime T: type,
    value: T,
    options: codec.EncodeOptions,
) usize {
    var counter: std.Io.Writer.Discarding = .init(&.{});
    encodeToWriter(T, value, options, &counter.writer) catch unreachable;
    return @intCast(counter.count + counter.writer.end);
}
