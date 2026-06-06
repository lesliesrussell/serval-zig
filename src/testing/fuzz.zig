// serval-1f7
//! Fuzz harness body: decoders must never crash on arbitrary input — every
//! outcome is a value or a DecodeError. Wired up via tests/fuzz_test.zig
//! (`zig build test --fuzz`).

const std = @import("std");
const json = @import("serval-json");
const msgpack = @import("serval-msgpack");

/// Exercises schema features: renames, constraints, optionals, defaults,
/// nesting, slices, enums.
pub const Target = struct {
    id: u64,
    name: []const u8,
    age: ?u8 = null,
    ratio: f64 = 0,
    tags: []const i64 = &.{},
    inner: struct { x: f32 = 0 } = .{},
    level: enum { low, high } = .low,

    pub const serval = .{
        .rename_all = .camel_case,
        .fields = .{ .name = .{ .min_len = 1 } },
    };
};

/// Throw `input` at every in-tree decoder; all errors are expected
/// outcomes. ZON is excluded — std.zig.Ast's recursion is not ours to
/// bound.
pub fn decodeAllBackends(gpa: std.mem.Allocator, input: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    _ = json.decode(Target, a, input, .{}) catch {};
    _ = json.decode(Target, a, input, .{ .unknown_fields = .collect, .validation = .lax }) catch {};
    _ = json.decodeValue(a, input, .{}) catch {};
    _ = msgpack.decode(Target, a, input, .{}) catch {};
    _ = msgpack.decode(Target, a, input, .{ .unknown_fields = .collect, .validation = .lax }) catch {};
    _ = msgpack.decodeValue(a, input, .{}) catch {};
}
