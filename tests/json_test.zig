// serval-15q
const std = @import("std");
const serval = @import("serval");

const fixtures = serval.testing.fixtures;
const User = fixtures.User;

test "json decode into typed struct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = try serval.json.decode(User, arena.allocator(), fixtures.sample_user_json, .{});
    try std.testing.expectEqual(@as(u64, 1), user.id);
    try std.testing.expectEqualStrings("ada", user.name);
    try std.testing.expectEqualStrings("ada@example.com", user.email);
    try std.testing.expectEqual(@as(?u8, 36), user.age);
}

test "json decode fills defaults for missing fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = try serval.json.decode(User, arena.allocator(),
        \\{"id":2,"name":"grace"}
    , .{});
    try std.testing.expectEqualStrings("", user.email);
    try std.testing.expectEqual(@as(?u8, null), user.age);
}

test "json decode rejects unknown fields by default" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.json.decode(User, arena.allocator(),
        \\{"id":3,"name":"linus","shoe_size":44}
    , .{});
    try std.testing.expectError(error.UnknownField, result);
}

test "json decode ignores unknown fields when asked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = try serval.json.decode(User, arena.allocator(),
        \\{"id":3,"name":"linus","shoe_size":44}
    , .{ .unknown_fields = .ignore });
    try std.testing.expectEqual(@as(u64, 3), user.id);
}

test "json encode" {
    const point = struct { x: i32, y: i32 }{ .x = 1, .y = 2 };
    const encoded = try serval.json.encodeAlloc(@TypeOf(point), std.testing.allocator, point, .{});
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings(
        \\{"x":1,"y":2}
    , encoded);
}

test "json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = User{ .id = 7, .name = "kay", .email = "kay@example.com", .age = 21 };
    try serval.testing.roundtrip.expectRoundtrip(User, arena.allocator(), user);
}
