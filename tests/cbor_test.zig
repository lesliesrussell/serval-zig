// serval-7jg
const std = @import("std");
const serval = @import("serval");

const User = serval.testing.fixtures.User;

test "cbor wire bytes: known encodings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const P = struct { x: i32 };
    // map(1) text(1) "x" uint(1)
    try std.testing.expectEqualSlices(u8, &.{ 0xa1, 0x61, 'x', 0x01 }, try serval.cbor.encodeAlloc(P, a, .{ .x = 1 }, .{}));
    // negative: -100 → major 1, ai 24, 99
    try std.testing.expectEqualSlices(u8, &.{ 0xa1, 0x61, 'x', 0x38, 0x63 }, try serval.cbor.encodeAlloc(P, a, .{ .x = -100 }, .{}));

    const Blob = struct {
        data: []const u8,

        pub const serval = .{ .bytes_policy = .bytes };
    };
    // byte string: major 2, len 3
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xa1, 0x64, 'd', 'a', 't', 'a', 0x43, 1, 2, 255 },
        try serval.cbor.encodeAlloc(Blob, a, .{ .data = &.{ 1, 2, 255 } }, .{}),
    );
}

test "cbor roundtrip: full schema feature struct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const user = User{ .id = 7, .name = "kay", .email = "k@e.io", .age = 21 };
    try std.testing.expectEqualDeep(user, try serval.cbor.decode(User, a, try serval.cbor.encodeAlloc(User, a, user, .{}), .{}));

    const N = struct { a: u8, b: i8, c: u64, d: i64, f: f64, g: f32, on: bool, opt: ?u8 = null, tags: []const i64 };
    const n = N{ .a = 200, .b = -100, .c = std.math.maxInt(u64), .d = std.math.minInt(i64), .f = 1.5, .g = 0.25, .on = true, .tags = &.{ 1, -2 } };
    try std.testing.expectEqualDeep(n, try serval.cbor.decode(N, a, try serval.cbor.encodeAlloc(N, a, n, .{}), .{}));
}

test "cbor rename_all and f16 decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Msg = struct {
        user_id: u64,

        pub const serval = .{ .rename_all = .camel_case };
    };
    const encoded = try serval.cbor.encodeAlloc(Msg, a, .{ .user_id = 5 }, .{});
    try std.testing.expectEqualSlices(u8, &.{ 0xa1, 0x66, 'u', 's', 'e', 'r', 'I', 'd', 0x05 }, encoded);
    try std.testing.expectEqualDeep(Msg{ .user_id = 5 }, try serval.cbor.decode(Msg, a, encoded, .{}));

    // f16 1.0 = 0x3c00 — decodes into f64 fields
    const F = struct { x: f64 };
    const f16_doc = [_]u8{ 0xa1, 0x61, 'x', 0xf9, 0x3c, 0x00 };
    const f = try serval.cbor.decode(F, a, &f16_doc, .{});
    try std.testing.expectEqual(@as(f64, 1.0), f.x);
}

test "cbor unions: all four tagging modes roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Ext = union(enum) { ping: void, count: u32 };
    inline for (.{ Ext{ .ping = {} }, Ext{ .count = 9 } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.cbor.decode(Ext, a, try serval.cbor.encodeAlloc(Ext, a, v, .{}), .{}));
    }

    const Int = union(enum) {
        circle: struct { r: f64 },
        point: void,

        pub const serval = .{ .union_tagging = .internal, .union_tag_field = "kind" };
    };
    inline for (.{ Int{ .circle = .{ .r = 2.5 } }, Int{ .point = {} } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.cbor.decode(Int, a, try serval.cbor.encodeAlloc(Int, a, v, .{}), .{}));
    }

    const Adj = union(enum) {
        start: void,
        move: struct { x: i32 },

        pub const serval = .{ .union_tagging = .adjacent, .union_tag_field = "t", .union_content_field = "c" };
    };
    inline for (.{ Adj{ .start = {} }, Adj{ .move = .{ .x = -4 } } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.cbor.decode(Adj, a, try serval.cbor.encodeAlloc(Adj, a, v, .{}), .{}));
    }

    const Un = union(enum) {
        num: i64,
        words: []const u8,

        pub const serval = .{ .union_tagging = .untagged };
    };
    inline for (.{ Un{ .num = 42 }, Un{ .words = "hi" } }) |v| {
        try std.testing.expectEqualDeep(v, try serval.cbor.decode(Un, a, try serval.cbor.encodeAlloc(Un, a, v, .{}), .{}));
    }
}

test "cbor pipeline: validation, unknown modes, presence, coercion, transforms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Limits = struct {
        name: []const u8,

        pub const serval = .{ .fields = .{ .name = .{ .min_len = 2, .trim = true } } };
    };
    const bad = try serval.cbor.encodeAlloc(Limits, a, .{ .name = "a" }, .{});
    try std.testing.expectError(error.ValidationFailed, serval.cbor.decode(Limits, a, bad, .{}));
    const dr = try serval.cbor.decodeResult(Limits, a, bad, .{});
    try std.testing.expectEqual(serval.core.IssueCode.min_len, dr.invalid.issues[0].code);

    // transform applies before constraints
    const padded = try serval.cbor.encodeAlloc(Limits, a, .{ .name = "  ok  " }, .{});
    const t = try serval.cbor.decode(Limits, a, padded, .{});
    try std.testing.expectEqualStrings("ok", t.name);

    // unknown fields
    const Wide = struct { id: u64, extra: i64 };
    const Narrow = struct { id: u64 };
    const wide = try serval.cbor.encodeAlloc(Wide, a, .{ .id = 1, .extra = -5 }, .{});
    try std.testing.expectError(error.UnknownField, serval.cbor.decode(Narrow, a, wide, .{}));
    const collected = try serval.cbor.decodeResult(Narrow, a, wide, .{ .unknown_fields = .collect });
    try std.testing.expectEqual(@as(i64, -5), collected.ok.unknown[0].value.int);

    // coercion
    const SWire = struct { age: []const u8 };
    const STarget = struct { age: u8 };
    const senc = try serval.cbor.encodeAlloc(SWire, a, .{ .age = "42" }, .{});
    const sv = try serval.cbor.decode(STarget, a, senc, .{ .coercion = .safe });
    try std.testing.expectEqual(@as(u8, 42), sv.age);
}

test "cbor borrowed: zero allocations for flat escape-free input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Contact = struct { name: []const u8, id: u64 };
    const encoded = try serval.cbor.encodeAlloc(Contact, arena.allocator(), .{ .name = "ada", .id = 1 }, .{});
    const b = try serval.cbor.decodeBorrowed(Contact, std.testing.failing_allocator, encoded, .{ .validation = .none });
    try std.testing.expectEqualStrings("ada", b.value.name);
    const lo = @intFromPtr(encoded.ptr);
    try std.testing.expect(@intFromPtr(b.value.name.ptr) >= lo and @intFromPtr(b.value.name.ptr) < lo + encoded.len);
}

test "cbor streaming + measure + rejects tags/indefinite/truncated/deep" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const P = struct { x: i32 };
    const encoded = try serval.cbor.encodeAlloc(P, a, .{ .x = 1000 }, .{});

    var reader = std.Io.Reader.fixed(encoded);
    try std.testing.expectEqual(@as(i32, 1000), (try serval.cbor.decodeFromReader(P, a, &reader, .{})).x);
    try std.testing.expectEqual(encoded.len, serval.cbor.measureEncodedLen(P, .{ .x = 1000 }, .{}));

    // tag (major 6) rejected
    try std.testing.expectError(error.UnexpectedToken, serval.cbor.decodeValue(a, &.{ 0xc1, 0x01 }, .{}));
    // indefinite array rejected
    try std.testing.expectError(error.UnexpectedToken, serval.cbor.decodeValue(a, &.{ 0x9f, 0x01, 0xff }, .{}));
    // truncated
    try std.testing.expectError(error.UnexpectedEndOfInput, serval.cbor.decode(P, a, encoded[0 .. encoded.len - 1], .{}));
    // pathological nesting: 0x81 = array(1), 2048 levels deep
    var deep: [2048]u8 = undefined;
    @memset(&deep, 0x81);
    deep[deep.len - 1] = 0x01;
    try std.testing.expectError(error.InvalidSyntax, serval.cbor.decodeValue(a, &deep, .{}));
}
