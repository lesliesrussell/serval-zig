// serval-1f7
//! Fuzz harness. `zig build test` runs the corpus as a smoke test;
//! `zig build test --fuzz` runs the real fuzzer.
//!
//! Known issue: Zig 0.16.0's fuzz-mode test_runner has an upstream
//! compile error (builtin.StackTrace vs debug.StackTrace mismatch in
//! compiler/test_runner.zig:566) — --fuzz is blocked until a toolchain
//! fix; the smoke path below still exercises every corpus entry.

const std = @import("std");
const serval = @import("serval");

test "fuzz: decoders return errors, never crash" {
    try std.testing.fuzz({}, fuzzOne, .{ .corpus = &.{
        \\{"id":1,"name":"a","tags":[1,2],"inner":{"x":0.5}}
        ,
        "\x82\xa2id\x01\xa4name\xa1a",
        "[[[[[",
        "\x91\x91\x91\x91",
        "\xdc\xff\xff",
        "{\"name\":\"\\u00",
    } });
}

fn fuzzOne(_: void, s: *std.testing.Smith) anyerror!void {
    var buf: [4096]u8 = undefined;
    const n = s.sliceWithHash(&buf, 0x5e7a1);
    serval.testing.fuzz.decodeAllBackends(std.testing.allocator, buf[0..n]);
}

test "msgpack: pathological nesting depth is an error, not a crash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var deep: [2048]u8 = undefined;
    @memset(&deep, 0x91); // fixarray(1), 2048 levels
    deep[deep.len - 1] = 0xc0; // nil

    try std.testing.expectError(error.InvalidSyntax, serval.msgpack.decodeValue(arena.allocator(), &deep, .{}));
}

test "json: pathological nesting depth is an error, not a crash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var deep: [4096]u8 = undefined;
    @memset(&deep, '[');

    // The scanner's fixed nesting buffer overflows — reported as OOM.
    try std.testing.expectError(error.OutOfMemory, serval.json.decodeValue(arena.allocator(), &deep, .{}));
}
