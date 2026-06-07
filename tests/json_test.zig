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

// serval-sru
test "decodeResult: nested missing required field carries full path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Outer = struct { inner: struct { x: i32 } };
    const dr = try serval.json.decodeResult(Outer, arena.allocator(),
        \\{"inner":{}}
    , .{});
    const segs = dr.invalid.issues[0].path.segments;
    try std.testing.expectEqual(serval.core.IssueCode.required, dr.invalid.issues[0].code);
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("inner", segs[0].field);
    try std.testing.expectEqualStrings("x", segs[1].field);
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

// serval-ee8
test "collect mode: unknown fields captured as Values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Known = struct { id: u64 };
    const dr = try serval.json.decodeResult(Known, arena.allocator(),
        \\{"id":3,"shoe_size":44,"ratio":1.5,"meta":{"tags":[1,true,null,"s"]}}
    , .{ .unknown_fields = .collect });

    try std.testing.expectEqual(@as(u64, 3), dr.ok.value.id);
    const unknown = dr.ok.unknown;
    try std.testing.expectEqual(@as(usize, 3), unknown.len);

    try std.testing.expectEqualStrings("shoe_size", unknown[0].name);
    try std.testing.expectEqual(@as(i64, 44), unknown[0].value.int);

    try std.testing.expectEqualStrings("ratio", unknown[1].name);
    try std.testing.expectEqual(@as(f64, 1.5), unknown[1].value.float);

    try std.testing.expectEqualStrings("meta", unknown[2].name);
    const meta = unknown[2].value.object;
    try std.testing.expectEqualStrings("tags", meta[0].name);
    const tags = meta[0].value.array;
    try std.testing.expectEqual(@as(i64, 1), tags[0].int);
    try std.testing.expect(tags[1].bool);
    try std.testing.expect(tags[2] == .null);
    try std.testing.expectEqualStrings("s", tags[3].string);
}

test "collect mode: no unknowns yields empty slice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Known = struct { id: u64 };
    const dr = try serval.json.decodeResult(Known, arena.allocator(),
        \\{"id":1}
    , .{ .unknown_fields = .collect });
    try std.testing.expectEqual(@as(usize, 0), dr.ok.unknown.len);
}

test "collect mode: nested struct unknowns are skipped not collected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Outer = struct { inner: struct { x: i32 } };
    const dr = try serval.json.decodeResult(Outer, arena.allocator(),
        \\{"inner":{"x":1,"extra":true},"top_extra":2}
    , .{ .unknown_fields = .collect });
    try std.testing.expectEqual(@as(i32, 1), dr.ok.value.inner.x);
    try std.testing.expectEqual(@as(usize, 1), dr.ok.unknown.len);
    try std.testing.expectEqualStrings("top_extra", dr.ok.unknown[0].name);
}

// serval-plc
const Shape = union(enum) {
    circle: struct { r: f64 },
    rect: struct { w: f64, h: f64 },
    point: void,

    pub const serval = .{
        .union_tagging = .internal,
        .union_tag_field = "kind",
    };
};

test "internal union: encode splices tag into payload" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const s = Shape{ .rect = .{ .w = 2, .h = 3 } };
    const encoded = try serval.json.encodeAlloc(Shape, arena.allocator(), s, .{});
    try std.testing.expectEqualStrings(
        \\{"kind":"rect","w":2,"h":3}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Shape, arena.allocator(), s);
}

test "internal union: tag position independent on decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const s = try serval.json.decode(Shape, arena.allocator(),
        \\{"r":2.5,"kind":"circle"}
    , .{});
    try std.testing.expectEqual(@as(f64, 2.5), s.circle.r);
}

test "internal union: void variant is tag-only object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const s = Shape{ .point = {} };
    const encoded = try serval.json.encodeAlloc(Shape, arena.allocator(), s, .{});
    try std.testing.expectEqualStrings(
        \\{"kind":"point"}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Shape, arena.allocator(), s);
}

test "internal union: unknown tag is decode error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.json.decode(Shape, arena.allocator(),
        \\{"kind":"blob"}
    , .{});
    try std.testing.expectError(error.InvalidEnumTag, result);
}

test "internal union: int payload field accepts whole-number JSON" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const s = try serval.json.decode(Shape, arena.allocator(),
        \\{"kind":"circle","r":2}
    , .{});
    try std.testing.expectEqual(@as(f64, 2), s.circle.r);
}

// serval-plc
const Mixed = union(enum) {
    num: i64,
    words: []const u8,
    pair: struct { a: i64, b: i64 },

    pub const serval = .{ .union_tagging = .untagged };
};

test "untagged union: variants matched by shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const n = try serval.json.decode(Mixed, arena.allocator(), "42", .{});
    try std.testing.expectEqual(@as(i64, 42), n.num);

    const w = try serval.json.decode(Mixed, arena.allocator(),
        \\"hi"
    , .{});
    try std.testing.expectEqualStrings("hi", w.words);

    const p = try serval.json.decode(Mixed, arena.allocator(),
        \\{"a":1,"b":2}
    , .{});
    try std.testing.expectEqual(@as(i64, 2), p.pair.b);
}

test "untagged union: encode emits payload bare" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const m = Mixed{ .pair = .{ .a = 1, .b = 2 } };
    const encoded = try serval.json.encodeAlloc(Mixed, arena.allocator(), m, .{});
    try std.testing.expectEqualStrings(
        \\{"a":1,"b":2}
    , encoded);
    try serval.testing.roundtrip.expectRoundtrip(Mixed, arena.allocator(), m);
}

test "untagged union: no matching variant is decode error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.json.decode(Mixed, arena.allocator(), "true", .{});
    try std.testing.expectError(error.InvalidEnumTag, result);
}

// serval-x09
test "decodeFromReader: streaming source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var reader = std.Io.Reader.fixed(fixtures.sample_user_json);
    const user = try serval.json.decodeFromReader(User, arena.allocator(), &reader, .{});
    try std.testing.expectEqual(@as(u64, 1), user.id);
    try std.testing.expectEqualStrings("ada", user.name);
}

test "decodeFromReader: validation still applies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var reader = std.Io.Reader.fixed(
        \\{"name":"a"}
    );
    const result = serval.json.decodeFromReader(Limits, arena.allocator(), &reader, .{});
    try std.testing.expectError(error.ValidationFailed, result);
}

test "encodeToWriter: writes through std.Io.Writer" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const point = struct { x: i32, y: i32 }{ .x = 1, .y = 2 };
    try serval.json.encodeToWriter(@TypeOf(point), point, .{}, &w);
    try std.testing.expectEqualStrings(
        \\{"x":1,"y":2}
    , w.buffered());
}

test "measureEncodedLen matches encodeAlloc" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = User{ .id = 7, .name = "kay", .email = "k@e.io", .age = 21 };
    const encoded = try serval.json.encodeAlloc(User, arena.allocator(), user, .{});
    try std.testing.expectEqual(encoded.len, serval.json.measureEncodedLen(User, user, .{}));
}

// serval-l3p
test "decodeValue: public dynamic decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v = try serval.json.decodeValue(arena.allocator(),
        \\{"id":3,"name":"ada","tags":[1,2.5,true,null]}
    , .{});
    const obj = v.object;
    try std.testing.expectEqualStrings("id", obj[0].name);
    try std.testing.expectEqual(@as(i64, 3), obj[0].value.int);
    try std.testing.expectEqualStrings("ada", obj[1].value.string);
    const tags = obj[2].value.array;
    try std.testing.expectEqual(@as(i64, 1), tags[0].int);
    try std.testing.expectEqual(@as(f64, 2.5), tags[1].float);
    try std.testing.expect(tags[2].bool);
    try std.testing.expect(tags[3] == .null);
}

test "decodeValue: trailing garbage rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = serval.json.decodeValue(arena.allocator(), "1 2", .{});
    try std.testing.expectError(error.InvalidSyntax, result);
}

test "schema-driven flow: decodeValue then valueAgainstSchema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dyn = try serval.json.decodeValue(arena.allocator(),
        \\{"name":"a"}
    , .{});
    const report = try serval.validate.valueAgainstSchema(Limits, dyn, arena.allocator(), .{});
    try std.testing.expect(!report.ok());
    try std.testing.expectEqual(serval.core.IssueCode.min_len, report.issues[0].code);
}

// serval-4tr
const Coercible = struct {
    age: u8 = 0,
    score: f64 = 0,
    active: bool = false,
    label: []const u8 = "",
};

test "coercion none: type mismatches are errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(Coercible, arena.allocator(),
        \\{"age":"42"}
    , .{}));
}

test "coercion safe: lossless conversions accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v = try serval.json.decode(Coercible, arena.allocator(),
        \\{"age":"42","score":"2.5","active":"true"}
    , .{ .coercion = .safe });
    try std.testing.expectEqual(@as(u8, 42), v.age);
    try std.testing.expectEqual(@as(f64, 2.5), v.score);
    try std.testing.expect(v.active);
}

test "coercion safe: lossy conversions still rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // float → int
    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(Coercible, a,
        \\{"age":1.5}
    , .{ .coercion = .safe }));
    // junk string → int
    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(Coercible, a,
        \\{"age":"4x"}
    , .{ .coercion = .safe }));
    // number → string
    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(Coercible, a,
        \\{"label":42}
    , .{ .coercion = .safe }));
}

test "coercion aggressive: lossy conversions with defined semantics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const v = try serval.json.decode(Coercible, a,
        \\{"age":41.9,"active":1,"label":42}
    , .{ .coercion = .aggressive });
    try std.testing.expectEqual(@as(u8, 41), v.age); // trunc toward zero
    try std.testing.expect(v.active); // 1 → true
    try std.testing.expectEqualStrings("42", v.label); // number token text

    const w = try serval.json.decode(Coercible, a,
        \\{"label":true}
    , .{ .coercion = .aggressive });
    try std.testing.expectEqualStrings("true", w.label);

    // bool → int
    const B = struct { n: u8 };
    const b = try serval.json.decode(B, a,
        \\{"n":true}
    , .{ .coercion = .aggressive });
    try std.testing.expectEqual(@as(u8, 1), b.n);

    // out-of-range float → int is Overflow, not wraparound
    try std.testing.expectError(error.Overflow, serval.json.decode(Coercible, a,
        \\{"age":300.5}
    , .{ .coercion = .aggressive }));
    // int 2 → bool is not a thing
    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(Coercible, a,
        \\{"active":2}
    , .{ .coercion = .aggressive }));
}

test "coercion flows into buffered union payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Shape2 = union(enum) {
        circle: struct { r: f64 },

        pub const serval = .{ .union_tagging = .internal, .union_tag_field = "kind" };
    };
    const s = try serval.json.decode(Shape2, arena.allocator(),
        \\{"kind":"circle","r":"2.5"}
    , .{ .coercion = .safe });
    try std.testing.expectEqual(@as(f64, 2.5), s.circle.r);
}

// serval-au2
const Login = struct {
    email: []const u8,
    code: ?[]const u8 = null,

    pub const serval = .{
        .fields = .{
            .email = .{ .trim = true, .lowercase = true, .email = true },
            .code = .{ .trim = true },
        },
    };
};

test "transforms: trim and lowercase before constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // raw input would fail the .email rule; the transformed value passes
    const v = try serval.json.decode(Login, arena.allocator(),
        \\{"email":"  Ada@Example.COM \n","code":" 42 "}
    , .{});
    try std.testing.expectEqualStrings("ada@example.com", v.email);
    try std.testing.expectEqualStrings("42", v.code.?);
}

test "transforms: trim preserves zero-alloc borrowed decode" {
    const Tag = struct {
        name: []const u8,

        pub const serval = .{ .fields = .{ .name = .{ .trim = true } } };
    };
    const input =
        \\{"name":"  ada  "}
    ;
    const b = try serval.json.decodeBorrowed(Tag, std.testing.failing_allocator, input, .{ .validation = .none });
    try std.testing.expectEqualStrings("ada", b.value.name);
    // trimmed slice still points into the input buffer
    const lo = @intFromPtr(input.ptr);
    try std.testing.expect(@intFromPtr(b.value.name.ptr) >= lo and @intFromPtr(b.value.name.ptr) < lo + input.len);
}

test "transforms: apply on buffered union payloads (fromValue path)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Cmd = union(enum) {
        login: struct {
            user: []const u8,

            pub const serval = .{ .fields = .{ .user = .{ .trim = true, .lowercase = true } } };
        },

        pub const serval = .{ .union_tagging = .internal, .union_tag_field = "kind" };
    };
    const c = try serval.json.decode(Cmd, arena.allocator(),
        \\{"kind":"login","user":" ADA "}
    , .{});
    try std.testing.expectEqualStrings("ada", c.login.user);
}

// serval-tsm
const Overlap = union(enum) {
    count: i64,
    ratio: f64,
    words: []const u8,

    pub const serval = .{ .union_tagging = .untagged, .untagged_policy = .unambiguous };
};

test "untagged .unambiguous: multi-variant match is an error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // 42 matches both i64 and f64 (ints feed float fields) — ambiguous.
    const result = serval.json.decode(Overlap, arena.allocator(), "42", .{});
    try std.testing.expectError(error.AmbiguousUnion, result);
}

test "untagged .unambiguous: single-variant matches still decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const f = try serval.json.decode(Overlap, a, "1.5", .{});
    try std.testing.expectEqual(@as(f64, 1.5), f.ratio);

    const w = try serval.json.decode(Overlap, a,
        \\"hi"
    , .{});
    try std.testing.expectEqualStrings("hi", w.words);

    // no variant matches at all
    try std.testing.expectError(error.InvalidEnumTag, serval.json.decode(Overlap, a, "true", .{}));
}

test "untagged default .first_match: declaration order wins on overlap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const FirstWins = union(enum) {
        count: i64,
        ratio: f64,

        pub const serval = .{ .union_tagging = .untagged };
    };
    const v = try serval.json.decode(FirstWins, arena.allocator(), "42", .{});
    try std.testing.expectEqual(@as(i64, 42), v.count);
}

// serval-47j
test "borrowed observability: allocated flag reflects forced allocations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Contact = struct { name: []const u8 };
    // escape-free: pure borrow, no allocations
    const clean = try serval.json.decodeBorrowed(Contact, arena.allocator(),
        \\{"name":"ada"}
    , .{ .validation = .none });
    try std.testing.expect(!clean.allocated);

    // escaped string forces an allocation
    const escaped = try serval.json.decodeBorrowed(Contact, arena.allocator(),
        \\{"name":"a\nb"}
    , .{ .validation = .none });
    try std.testing.expect(escaped.allocated);
}

test "borrowed observability: zeroAllocEligible predicts the failing_allocator outcome" {
    const Flat = struct { name: []const u8, id: u64, on: bool, age: ?u8 = null, nested: struct { x: f64 = 0 } = .{} };
    const HasSlice = struct { xs: []const i64 };
    const HasUnion = struct { u: union(enum) { a: u8 } };
    const HasLowercase = struct {
        s: []const u8,

        pub const serval = .{ .fields = .{ .s = .{ .lowercase = true } } };
    };
    const HasTrim = struct {
        s: []const u8,

        pub const serval = .{ .fields = .{ .s = .{ .trim = true } } };
    };

    comptime {
        std.debug.assert(serval.codec.zeroAllocEligible(Flat));
        std.debug.assert(serval.codec.zeroAllocEligible(HasTrim));
        std.debug.assert(!serval.codec.zeroAllocEligible(HasSlice));
        std.debug.assert(!serval.codec.zeroAllocEligible(HasUnion));
        std.debug.assert(!serval.codec.zeroAllocEligible(HasLowercase));
    }

    // the eligible type really does decode with the failing allocator
    const b = try serval.json.decodeBorrowed(Flat, std.testing.failing_allocator,
        \\{"name":"ada","id":1,"on":true,"nested":{"x":0.5}}
    , .{ .validation = .none });
    try std.testing.expect(!b.allocated);
    try std.testing.expectEqualStrings("ada", b.value.name);
}

test "json roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = User{ .id = 7, .name = "kay", .email = "kay@example.com", .age = 21 };
    try serval.testing.roundtrip.expectRoundtrip(User, arena.allocator(), user);
}
