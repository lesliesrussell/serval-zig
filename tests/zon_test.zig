// serval-9kw
const std = @import("std");
const serval = @import("serval");

const Config = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    tags: []const []const u8 = &.{},
    mode: enum { dev, prod } = .dev,
    timeout: ?u32 = null,
};

test "zon decode struct with defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cfg = try serval.zon.decode(Config, arena.allocator(),
        \\.{ .host = "example.com", .mode = .prod, .tags = .{ "a", "b" } }
    , .{ .memory = .arena });
    try std.testing.expectEqualStrings("example.com", cfg.host);
    try std.testing.expectEqual(@as(u16, 8080), cfg.port);
    try std.testing.expectEqual(.prod, cfg.mode);
    try std.testing.expectEqual(@as(usize, 2), cfg.tags.len);
    try std.testing.expectEqual(@as(?u32, null), cfg.timeout);
}

test "zon decode: syntax error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.zon.decode(Config, arena.allocator(), ".{ nope", .{ .memory = .arena });
    try std.testing.expectError(error.InvalidSyntax, result);
}

test "zon decode: unknown field rejected by default, ignorable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const rejected = serval.zon.decode(Config, arena.allocator(),
        \\.{ .host = "x", .extra = 1 }
    , .{ .memory = .arena });
    try std.testing.expectError(error.InvalidSyntax, rejected);

    const ok = try serval.zon.decode(Config, arena.allocator(),
        \\.{ .host = "x", .extra = 1 }
    , .{ .memory = .arena, .unknown_fields = .ignore });
    try std.testing.expectEqualStrings("x", ok.host);
}

const Limits = struct {
    name: []const u8,

    pub const serval = .{ .fields = .{ .name = .{ .min_len = 2 } } };
};

test "zon decode: validation integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const strict = serval.zon.decode(Limits, arena.allocator(),
        \\.{ .name = "a" }
    , .{ .memory = .arena });
    try std.testing.expectError(error.ValidationFailed, strict);

    const dr = try serval.zon.decodeResult(Limits, arena.allocator(),
        \\.{ .name = "a" }
    , .{ .memory = .arena });
    try std.testing.expectEqual(serval.core.IssueCode.min_len, dr.invalid.issues[0].code);

    const lax = try serval.zon.decodeResult(Limits, arena.allocator(),
        \\.{ .name = "a" }
    , .{ .memory = .arena, .validation = .lax });
    try std.testing.expectEqualStrings("a", lax.ok.value.name);
    try std.testing.expect(!lax.ok.warnings.ok());
}

test "zon encode and roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const cfg = Config{ .host = "h", .port = 1, .tags = &.{"t"}, .mode = .prod, .timeout = 9 };
    const encoded = try serval.zon.encodeAlloc(Config, arena.allocator(), cfg, .{});
    const back = try serval.zon.decode(Config, arena.allocator(), encoded, .{ .memory = .arena });
    try std.testing.expectEqualDeep(cfg, back);
}

test "zon encode minified vs pretty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const P = struct { x: i32 };
    const min = try serval.zon.encodeAlloc(P, arena.allocator(), .{ .x = 1 }, .{});
    try std.testing.expectEqualStrings(".{.x=1}", min);

    const pretty = try serval.zon.encodeAlloc(P, arena.allocator(), .{ .x = 1 }, .{ .pretty = true });
    try std.testing.expect(std.mem.indexOfScalar(u8, pretty, ' ') != null);
}
