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
    try std.testing.expectEqualStrings("ada", dr.ok.value.name);
    try std.testing.expect(dr.ok.warnings.ok());
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

// serval-w98
test "lax validation: value returned with constraint warnings attached" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dr = try serval.json.decodeResult(Limits, arena.allocator(),
        \\{"name":"a"}
    , .{ .validation = .lax });
    try std.testing.expectEqualStrings("a", dr.ok.value.name);
    try std.testing.expect(!dr.ok.warnings.ok());
    try std.testing.expectEqual(serval.core.IssueCode.min_len, dr.ok.warnings.issues[0].code);
}

test "lax validation: shape failures still invalid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dr = try serval.json.decodeResult(Limits, arena.allocator(), "{}", .{ .validation = .lax });
    try std.testing.expectEqual(serval.core.IssueCode.required, dr.invalid.issues[0].code);
}

test "lax validation: typed decode returns value despite warnings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v = try serval.json.decode(Limits, arena.allocator(),
        \\{"name":"a"}
    , .{ .validation = .lax });
    try std.testing.expectEqualStrings("a", v.name);
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
    try std.testing.expectEqualStrings("countess", with.ok.value.nickname);
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

// serval-vw4
test "encode honors rename_all wire names and roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Msg = struct {
        user_id: u64,
        display_name: []const u8,

        pub const serval = .{ .rename_all = .camel_case };
    };
    const msg = Msg{ .user_id = 5, .display_name = "ada" };
    const encoded = try serval.json.encodeAlloc(Msg, arena.allocator(), msg, .{});
    try std.testing.expectEqualStrings(
        \\{"userId":5,"displayName":"ada"}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Msg, arena.allocator(), msg);
}

test "encode nested struct, slices, optional null, enum name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Doc = struct {
        level: enum { low, high },
        age: ?u8 = null,
        tags: []const []const u8,
        inner: struct { x: i32 },
    };
    const doc = Doc{ .level = .high, .tags = &.{ "a", "b" }, .inner = .{ .x = -3 } };
    const encoded = try serval.json.encodeAlloc(Doc, arena.allocator(), doc, .{});
    try std.testing.expectEqualStrings(
        \\{"level":"high","age":null,"tags":["a","b"],"inner":{"x":-3}}
    , encoded);
}

test "enum_tagging .value roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Job = struct {
        state: enum(u8) { queued = 0, running = 1, done = 2 },

        pub const serval = .{ .enum_tagging = .value };
    };
    const job = Job{ .state = .running };
    const encoded = try serval.json.encodeAlloc(Job, arena.allocator(), job, .{});
    try std.testing.expectEqualStrings(
        \\{"state":1}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Job, arena.allocator(), job);
}

test "bytes_policy .bytes encodes number array and roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Blob = struct {
        data: []const u8,

        pub const serval = .{ .bytes_policy = .bytes };
    };
    const blob = Blob{ .data = &.{ 1, 2, 255 } };
    const encoded = try serval.json.encodeAlloc(Blob, arena.allocator(), blob, .{});
    try std.testing.expectEqualStrings(
        \\{"data":[1,2,255]}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Blob, arena.allocator(), blob);
}

test "encode escapes strings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const S = struct { s: []const u8 };
    const v = S{ .s = "a\"b\nc" };
    const encoded = try serval.json.encodeAlloc(S, arena.allocator(), v, .{});
    try std.testing.expectEqualStrings(
        \\{"s":"a\"b\nc"}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(S, arena.allocator(), v);
}

test "pretty encode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const P = struct { x: i32, tags: []const i32 };
    const encoded = try serval.json.encodeAlloc(P, arena.allocator(), .{ .x = 1, .tags = &.{ 2, 3 } }, .{ .pretty = true });
    try std.testing.expectEqualStrings(
        \\{
        \\  "x": 1,
        \\  "tags": [
        \\    2,
        \\    3
        \\  ]
        \\}
    , encoded);
}

test "encode empty containers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const E = struct { tags: []const i32 = &.{} };
    const encoded = try serval.json.encodeAlloc(E, arena.allocator(), .{}, .{});
    try std.testing.expectEqualStrings(
        \\{"tags":[]}
    , encoded);
}

// serval-x9g
const Event = union(enum) {
    ping: void,
    msg: struct { body: []const u8 },
    count: u32,
};

test "external union: payload variant roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ev = Event{ .count = 7 };
    const encoded = try serval.json.encodeAlloc(Event, arena.allocator(), ev, .{});
    try std.testing.expectEqualStrings(
        \\{"count":7}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Event, arena.allocator(), ev);
}

test "external union: struct payload roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ev = Event{ .msg = .{ .body = "hi" } };
    const encoded = try serval.json.encodeAlloc(Event, arena.allocator(), ev, .{});
    try std.testing.expectEqualStrings(
        \\{"msg":{"body":"hi"}}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Event, arena.allocator(), ev);
}

test "external union: void variant is a bare string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ev = Event{ .ping = {} };
    const encoded = try serval.json.encodeAlloc(Event, arena.allocator(), ev, .{});
    try std.testing.expectEqualStrings(
        \\"ping"
    , encoded);
    const decoded = try serval.json.decode(Event, arena.allocator(), encoded, .{});
    try std.testing.expectEqual(std.meta.Tag(Event).ping, std.meta.activeTag(decoded));
}

test "external union: unknown variant is decode error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.json.decode(Event, arena.allocator(),
        \\{"nope":1}
    , .{});
    try std.testing.expectError(error.InvalidEnumTag, result);
}

test "union nested in struct roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Envelope = struct { id: u32, event: Event };
    const env = Envelope{ .id = 1, .event = .{ .count = 3 } };
    const encoded = try serval.json.encodeAlloc(Envelope, arena.allocator(), env, .{});
    try std.testing.expectEqualStrings(
        \\{"id":1,"event":{"count":3}}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Envelope, arena.allocator(), env);
}

// serval-x9g
const Adjacent = union(enum) {
    start: void,
    move: struct { x: i32, y: i32 },

    pub const serval = .{
        .union_tagging = .adjacent,
        .union_tag_field = "t",
        .union_content_field = "c",
    };
};

test "adjacent union: payload variant roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const a = Adjacent{ .move = .{ .x = 1, .y = 2 } };
    const encoded = try serval.json.encodeAlloc(Adjacent, arena.allocator(), a, .{});
    try std.testing.expectEqualStrings(
        \\{"t":"move","c":{"x":1,"y":2}}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Adjacent, arena.allocator(), a);
}

test "adjacent union: void variant omits content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const a = Adjacent{ .start = {} };
    const encoded = try serval.json.encodeAlloc(Adjacent, arena.allocator(), a, .{});
    try std.testing.expectEqualStrings(
        \\{"t":"start"}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Adjacent, arena.allocator(), a);
}

test "union variant names honor rename_all" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Cmd = union(enum) {
        go_fast: u8,

        pub const serval = .{ .rename_all = .camel_case };
    };
    const cmd = Cmd{ .go_fast = 9 };
    const encoded = try serval.json.encodeAlloc(Cmd, arena.allocator(), cmd, .{});
    try std.testing.expectEqualStrings(
        \\{"goFast":9}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Cmd, arena.allocator(), cmd);
}

// serval-0mq
test "borrowed decode: strings point into the input buffer" {
    const input = try std.testing.allocator.dupe(u8,
        \\{"name":"ada","email":"ada@example.com"}
    );
    defer std.testing.allocator.free(input);

    const Contact = struct { name: []const u8, email: []const u8 };
    const b = try serval.json.decodeBorrowed(Contact, std.testing.allocator, input, .{ .validation = .none });

    const lo = @intFromPtr(input.ptr);
    const hi = lo + input.len;
    try std.testing.expect(@intFromPtr(b.value.name.ptr) >= lo and @intFromPtr(b.value.name.ptr) < hi);
    try std.testing.expect(@intFromPtr(b.value.email.ptr) >= lo and @intFromPtr(b.value.email.ptr) < hi);
    try std.testing.expectEqualStrings("ada", b.value.name);
}

test "borrowed decode: zero allocations for escape-free flat input" {
    const Contact = struct { name: []const u8, id: u64, active: bool };
    // failing_allocator errors on any allocation — decode must not touch it.
    const b = try serval.json.decodeBorrowed(Contact, std.testing.failing_allocator,
        \\{"name":"ada","id":1,"active":true}
    , .{ .validation = .none });
    try std.testing.expectEqualStrings("ada", b.value.name);
    try std.testing.expectEqual(@as(u64, 1), b.value.id);
}

test "borrowed decode: escaped strings fall back to allocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const S = struct { s: []const u8 };
    const b = try serval.json.decodeBorrowed(S, arena.allocator(),
        \\{"s":"a\nb"}
    , .{ .validation = .none });
    try std.testing.expectEqualStrings("a\nb", b.value.s);
}

test "borrowed decode: validation still works when requested" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Limited = struct {
        name: []const u8,

        pub const serval = .{ .fields = .{ .name = .{ .min_len = 2 } } };
    };
    const result = serval.json.decodeBorrowed(Limited, arena.allocator(),
        \\{"name":"a"}
    , .{});
    try std.testing.expectError(error.ValidationFailed, result);
}

test "json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = User{ .id = 7, .name = "kay", .email = "kay@example.com", .age = 21 };
    try serval.testing.roundtrip.expectRoundtrip(User, arena.allocator(), user);
}
