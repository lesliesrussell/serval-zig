// serval-bfi
const std = @import("std");
const serval = @import("serval");

const User = serval.testing.fixtures.User;

test "msgpack roundtrip: struct with defaults and optional" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const user = User{ .id = 7, .name = "kay", .email = "k@e.io", .age = 21 };
    const encoded = try serval.msgpack.encodeAlloc(User, arena.allocator(), user, .{});
    const back = try serval.msgpack.decode(User, arena.allocator(), encoded, .{});
    try std.testing.expectEqualDeep(user, back);
}

test "msgpack wire bytes: known encoding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const P = struct { x: i32 };
    const encoded = try serval.msgpack.encodeAlloc(P, arena.allocator(), .{ .x = 1 }, .{});
    // fixmap(1) "x" fixint(1)
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0xa1, 'x', 0x01 }, encoded);
}

test "msgpack int width selection roundtrips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const N = struct { a: u8, b: i8, c: u16, d: i32, e: u64, f: i64 };
    const n = N{ .a = 200, .b = -100, .c = 60000, .d = -2_000_000_000, .e = std.math.maxInt(u64), .f = std.math.minInt(i64) };
    const encoded = try serval.msgpack.encodeAlloc(N, arena.allocator(), n, .{});
    const back = try serval.msgpack.decode(N, arena.allocator(), encoded, .{});
    try std.testing.expectEqualDeep(n, back);
}

test "msgpack floats, bools, slices, nested" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Doc = struct {
        ratio: f64,
        small: f32,
        on: bool,
        scores: []const i64,
        inner: struct { s: []const u8 },
    };
    const doc = Doc{ .ratio = 1.5, .small = 0.25, .on = true, .scores = &.{ 1, -2, 300 }, .inner = .{ .s = "hi" } };
    const encoded = try serval.msgpack.encodeAlloc(Doc, arena.allocator(), doc, .{});
    const back = try serval.msgpack.decode(Doc, arena.allocator(), encoded, .{});
    try std.testing.expectEqualDeep(doc, back);
}

test "msgpack rename_all wire names roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Msg = struct {
        user_id: u64,

        pub const serval = .{ .rename_all = .camel_case };
    };
    const m = Msg{ .user_id = 5 };
    const encoded = try serval.msgpack.encodeAlloc(Msg, arena.allocator(), m, .{});
    // fixmap(1) fixstr(6) "userId" fixint(5)
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0xa6, 'u', 's', 'e', 'r', 'I', 'd', 0x05 }, encoded);
    try std.testing.expectEqualDeep(m, try serval.msgpack.decode(Msg, arena.allocator(), encoded, .{}));
}

test "msgpack bytes_policy .bytes uses bin format" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Blob = struct {
        data: []const u8,

        pub const serval = .{ .bytes_policy = .bytes };
    };
    const blob = Blob{ .data = &.{ 1, 2, 255 } };
    const encoded = try serval.msgpack.encodeAlloc(Blob, arena.allocator(), blob, .{});
    // fixmap(1) fixstr(4) "data" bin8(3) 1 2 255
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0xa4, 'd', 'a', 't', 'a', 0xc4, 0x03, 1, 2, 255 }, encoded);
    try std.testing.expectEqualDeep(blob, try serval.msgpack.decode(Blob, arena.allocator(), encoded, .{}));
}

test "msgpack enum tagging name and value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Named = struct { level: enum { low, high } };
    const n = Named{ .level = .high };
    try std.testing.expectEqualDeep(n, try serval.msgpack.decode(Named, arena.allocator(), try serval.msgpack.encodeAlloc(Named, arena.allocator(), n, .{}), .{}));

    const Valued = struct {
        state: enum(u8) { queued = 0, running = 1 },

        pub const serval = .{ .enum_tagging = .value };
    };
    const v = Valued{ .state = .running };
    const encoded = try serval.msgpack.encodeAlloc(Valued, arena.allocator(), v, .{});
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0xa5, 's', 't', 'a', 't', 'e', 0x01 }, encoded);
    try std.testing.expectEqualDeep(v, try serval.msgpack.decode(Valued, arena.allocator(), encoded, .{}));
}

test "msgpack unions: all four tagging modes roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Ext = union(enum) { ping: void, count: u32 };
    inline for (.{ Ext{ .ping = {} }, Ext{ .count = 9 } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.msgpack.decode(Ext, a, try serval.msgpack.encodeAlloc(Ext, a, v, .{}), .{}));
    }

    const Adj = union(enum) {
        start: void,
        move: struct { x: i32 },

        pub const serval = .{ .union_tagging = .adjacent, .union_tag_field = "t", .union_content_field = "c" };
    };
    inline for (.{ Adj{ .start = {} }, Adj{ .move = .{ .x = -4 } } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.msgpack.decode(Adj, a, try serval.msgpack.encodeAlloc(Adj, a, v, .{}), .{}));
    }

    const Int = union(enum) {
        circle: struct { r: f64 },
        point: void,

        pub const serval = .{ .union_tagging = .internal, .union_tag_field = "kind" };
    };
    inline for (.{ Int{ .circle = .{ .r = 2.5 } }, Int{ .point = {} } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.msgpack.decode(Int, a, try serval.msgpack.encodeAlloc(Int, a, v, .{}), .{}));
    }

    const Un = union(enum) {
        num: i64,
        words: []const u8,

        pub const serval = .{ .union_tagging = .untagged };
    };
    inline for (.{ Un{ .num = 42 }, Un{ .words = "hi" } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.msgpack.decode(Un, a, try serval.msgpack.encodeAlloc(Un, a, v, .{}), .{}));
    }
}

const Limits = struct {
    name: []const u8,

    pub const serval = .{ .fields = .{ .name = .{ .min_len = 2 } } };
};

test "msgpack validation integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const bad = Limits{ .name = "a" };
    const encoded = try serval.msgpack.encodeAlloc(Limits, arena.allocator(), bad, .{});
    try std.testing.expectError(error.ValidationFailed, serval.msgpack.decode(Limits, arena.allocator(), encoded, .{}));

    const dr = try serval.msgpack.decodeResult(Limits, arena.allocator(), encoded, .{});
    try std.testing.expectEqual(serval.core.IssueCode.min_len, dr.invalid.issues[0].code);
}

test "msgpack unknown fields: reject, ignore, collect" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Wide = struct { id: u64, extra: i64 };
    const Narrow = struct { id: u64 };
    const encoded = try serval.msgpack.encodeAlloc(Wide, a, .{ .id = 1, .extra = -5 }, .{});

    try std.testing.expectError(error.UnknownField, serval.msgpack.decode(Narrow, a, encoded, .{}));

    const ok = try serval.msgpack.decode(Narrow, a, encoded, .{ .unknown_fields = .ignore });
    try std.testing.expectEqual(@as(u64, 1), ok.id);

    const dr = try serval.msgpack.decodeResult(Narrow, a, encoded, .{ .unknown_fields = .collect });
    try std.testing.expectEqual(@as(usize, 1), dr.ok.unknown.len);
    try std.testing.expectEqualStrings("extra", dr.ok.unknown[0].name);
    try std.testing.expectEqual(@as(i64, -5), dr.ok.unknown[0].value.int);
}

test "msgpack presence tracking feeds ctx.has" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Profile = struct {
        name: []const u8,
        nickname: []const u8 = "",

        pub fn servalValidate(ctx: *serval.core.ValidateContext, self: *const @This()) void {
            _ = self;
            if (!ctx.has("nickname")) {
                ctx.issue(.{ .path = serval.core.Path.field("nickname"), .code = .required_when, .message = "required here" });
            }
        }
    };
    // encode a value whose nickname is the default — decode of the full
    // encoding includes the key, so it counts as present.
    const full = try serval.msgpack.encodeAlloc(Profile, arena.allocator(), .{ .name = "ada" }, .{});
    const dr = try serval.msgpack.decodeResult(Profile, arena.allocator(), full, .{});
    try std.testing.expect(dr == .ok);
}

test "msgpack borrowed: strings point into input" {
    const Contact = struct { name: []const u8 };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const encoded = try serval.msgpack.encodeAlloc(Contact, arena.allocator(), .{ .name = "ada" }, .{});
    const b = try serval.msgpack.decodeBorrowed(Contact, std.testing.failing_allocator, encoded, .{ .validation = .none });
    const lo = @intFromPtr(encoded.ptr);
    try std.testing.expect(@intFromPtr(b.value.name.ptr) >= lo and @intFromPtr(b.value.name.ptr) < lo + encoded.len);
}

test "msgpack streaming entry points" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const P = struct { x: i32 };
    const encoded = try serval.msgpack.encodeAlloc(P, arena.allocator(), .{ .x = 1 }, .{});

    var reader = std.Io.Reader.fixed(encoded);
    const back = try serval.msgpack.decodeFromReader(P, arena.allocator(), &reader, .{});
    try std.testing.expectEqual(@as(i32, 1), back.x);

    var buf: [16]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try serval.msgpack.encodeToWriter(P, .{ .x = 1 }, .{}, &w);
    try std.testing.expectEqualSlices(u8, encoded, w.buffered());

    try std.testing.expectEqual(encoded.len, serval.msgpack.measureEncodedLen(P, .{ .x = 1 }, .{}));
}

test "msgpack truncated input is decode error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const P = struct { x: i32 };
    const encoded = try serval.msgpack.encodeAlloc(P, arena.allocator(), .{ .x = 1000 }, .{});
    const result = serval.msgpack.decode(P, arena.allocator(), encoded[0 .. encoded.len - 1], .{});
    try std.testing.expectError(error.UnexpectedEndOfInput, result);
}
