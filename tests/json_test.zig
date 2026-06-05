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

// serval-r4h
test "decode honors rename_all wire names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Msg = struct {
        user_id: u64,
        display_name: []const u8,

        pub const serval = .{ .rename_all = .camel_case };
    };
    const msg = try serval.json.decode(Msg, arena.allocator(),
        \\{"userId":5,"displayName":"ada"}
    , .{});
    try std.testing.expectEqual(@as(u64, 5), msg.user_id);
    try std.testing.expectEqualStrings("ada", msg.display_name);
}

test "decode nested struct, enum, slices, escapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Level = enum { low, high };
    const Doc = struct {
        level: Level,
        tags: []const []const u8,
        inner: struct { x: i32, on: bool },
        scores: []const f64,
    };
    const doc = try serval.json.decode(Doc, arena.allocator(),
        \\{"level":"high","tags":["a","b\nc"],"inner":{"x":-3,"on":true},"scores":[1.5,2.0]}
    , .{});
    try std.testing.expectEqual(Level.high, doc.level);
    try std.testing.expectEqual(@as(usize, 2), doc.tags.len);
    try std.testing.expectEqualStrings("b\nc", doc.tags[1]);
    try std.testing.expectEqual(@as(i32, -3), doc.inner.x);
    try std.testing.expect(doc.inner.on);
    try std.testing.expectEqual(@as(f64, 1.5), doc.scores[0]);
}

const Limits = struct {
    name: []const u8,

    pub const serval = .{ .fields = .{ .name = .{ .min_len = 2 } } };
};

test "decodeResult: ok variant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dr = try serval.json.decodeResult(Limits, arena.allocator(),
        \\{"name":"ada"}
    , .{});
    try std.testing.expectEqualStrings("ada", dr.ok.name);
}

test "decodeResult: invalid on constraint violation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dr = try serval.json.decodeResult(Limits, arena.allocator(),
        \\{"name":"a"}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.min_len, dr.invalid.issues[0].code);
    try std.testing.expectEqualStrings("name", dr.invalid.issues[0].path.segments[0].field);
}

test "decodeResult: missing required field is a shape issue" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dr = try serval.json.decodeResult(Limits, arena.allocator(), "{}", .{});
    try std.testing.expectEqual(serval.core.IssueCode.required, dr.invalid.issues[0].code);
}

test "decodeResult: decode_error on syntax failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dr = try serval.json.decodeResult(Limits, arena.allocator(), "{nope", .{});
    try std.testing.expectEqual(serval.core.DecodeError.InvalidSyntax, dr.decode_error);
}

test "decode: strict validation failure surfaces as error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.json.decode(Limits, arena.allocator(),
        \\{"name":"a"}
    , .{});
    try std.testing.expectError(error.ValidationFailed, result);
}

test "decode: validation none skips constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v = try serval.json.decode(Limits, arena.allocator(),
        \\{"name":"a"}
    , .{ .validation = .none });
    try std.testing.expectEqualStrings("a", v.name);
}

test "presence tracking feeds ctx.has in custom validators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Profile = struct {
        name: []const u8,
        nickname: []const u8 = "",

        pub fn servalValidate(ctx: *serval.core.ValidateContext, self: *const @This()) void {
            _ = self;
            if (!ctx.has("nickname")) {
                ctx.issue(.{
                    .path = serval.core.Path.field("nickname"),
                    .code = .required_when,
                    .message = "nickname required on this endpoint",
                });
            }
        }
    };

    const without = try serval.json.decodeResult(Profile, arena.allocator(),
        \\{"name":"ada"}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.required_when, without.invalid.issues[0].code);

    const with = try serval.json.decodeResult(Profile, arena.allocator(),
        \\{"name":"ada","nickname":"countess"}
    , .{});
    try std.testing.expectEqualStrings("countess", with.ok.nickname);
}

test "decode: bad enum tag is decode error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const E = struct { level: enum { low, high } };
    const result = serval.json.decode(E, arena.allocator(),
        \\{"level":"medium"}
    , .{});
    try std.testing.expectError(error.InvalidEnumTag, result);
}

test "decode: trailing garbage rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.json.decode(Limits, arena.allocator(),
        \\{"name":"ada"} trailing
    , .{});
    try std.testing.expectError(error.InvalidSyntax, result);
}

test "json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = User{ .id = 7, .name = "kay", .email = "kay@example.com", .age = 21 };
    try serval.testing.roundtrip.expectRoundtrip(User, arena.allocator(), user);
}
