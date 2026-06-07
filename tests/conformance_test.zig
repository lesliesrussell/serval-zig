// serval-9a3
//! Cross-backend conformance suite enforcing SPEC §9: for any value
//! expressible in a backend's capability set, decode∘encode is identity,
//! and invalid inputs classify identically across backends.

const std = @import("std");
const serval = @import("serval");

/// Backends with the full capability set (issue-code matrix applies).
const full_backends = .{ serval.json, serval.msgpack, serval.cbor };
/// Backends asserted for roundtrip self-consistency only.
const all_backends = .{ serval.json, serval.msgpack, serval.cbor, serval.zon };

// --- Roundtrip matrix ---------------------------------------------------

/// Every schema feature in one type (renames apply to json/msgpack/cbor;
/// zon ignores them symmetrically, so self-roundtrip still holds).
const Sink = struct {
    u8_max: u8 = std.math.maxInt(u8),
    i8_min: i8 = std.math.minInt(i8),
    u64_max: u64 = std.math.maxInt(u64),
    i64_min: i64 = std.math.minInt(i64),
    f_64: f64 = -1234.5,
    f_32: f32 = 0.25,
    flag: bool = true,
    opt_null: ?u8 = null,
    opt_set: ?u8 = 7,
    text: []const u8 = "plain",
    escaped: []const u8 = "a\"b\nc",
    tags: []const i64 = &.{ 1, -2, 300 },
    names: []const []const u8 = &.{ "x", "y" },
    nested: struct { level: enum { low, high } = .high, x: i32 = -3 } = .{},

    pub const serval = .{ .rename_all = .camel_case };
};

test "conformance: Sink roundtrips identically through every backend" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const v = Sink{};
    inline for (all_backends) |B| {
        const encoded = try B.encodeAlloc(Sink, a, v, .{});
        const back = try B.decode(Sink, a, encoded, .{});
        try std.testing.expectEqualDeep(v, back);
    }
}

test "conformance: all four union tagging modes roundtrip per backend" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Ext = union(enum) { ping: void, count: u32 };
    const Adj = union(enum) {
        go: void,
        move: struct { x: i32 },

        pub const serval = .{ .union_tagging = .adjacent, .union_tag_field = "t", .union_content_field = "c" };
    };
    const Int = union(enum) {
        circle: struct { r: f64 },
        point: void,

        pub const serval = .{ .union_tagging = .internal, .union_tag_field = "kind" };
    };
    const Un = union(enum) {
        num: i64,
        words: []const u8,

        pub const serval = .{ .union_tagging = .untagged };
    };

    // zon excluded: std.zon has its own native union syntax and ignores
    // serval tagging metadata (declared capability gap).
    inline for (full_backends) |B| {
        inline for (.{ Ext{ .ping = {} }, Ext{ .count = 9 } }) |v| {
            try std.testing.expectEqualDeep(v, try B.decode(Ext, a, try B.encodeAlloc(Ext, a, v, .{}), .{}));
        }
        inline for (.{ Adj{ .go = {} }, Adj{ .move = .{ .x = -4 } } }) |v| {
            try std.testing.expectEqualDeep(v, try B.decode(Adj, a, try B.encodeAlloc(Adj, a, v, .{}), .{}));
        }
        inline for (.{ Int{ .circle = .{ .r = 2.5 } }, Int{ .point = {} } }) |v| {
            try std.testing.expectEqualDeep(v, try B.decode(Int, a, try B.encodeAlloc(Int, a, v, .{}), .{}));
        }
        inline for (.{ Un{ .num = 42 }, Un{ .words = "hi" } }) |v| {
            try std.testing.expectEqualDeep(v, try B.decode(Un, a, try B.encodeAlloc(Un, a, v, .{}), .{}));
        }
    }
}

test "conformance: bytes_policy and enum_tagging value roundtrip per backend" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Blob = struct {
        data: []const u8 = &.{ 0, 1, 255 },
        state: enum(u8) { idle = 0, busy = 3 } = .busy,

        pub const serval = .{ .bytes_policy = .bytes, .enum_tagging = .value };
    };
    inline for (full_backends) |B| {
        const v = Blob{};
        try std.testing.expectEqualDeep(v, try B.decode(Blob, a, try B.encodeAlloc(Blob, a, v, .{}), .{}));
    }
}

// --- Invalid-input matrix: identical classification ----------------------

const Limited = struct {
    name: []const u8,

    pub const serval = .{ .fields = .{ .name = .{ .min_len = 3 } } };
};

test "conformance: constraint violations produce the same issue code everywhere" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    inline for (full_backends) |B| {
        const bad = try B.encodeAlloc(Limited, a, .{ .name = "x" }, .{});
        const dr = try B.decodeResult(Limited, a, bad, .{});
        try std.testing.expectEqual(serval.core.IssueCode.min_len, dr.invalid.issues[0].code);
        try std.testing.expectEqualStrings("name", dr.invalid.issues[0].path.segments[0].field);
        try std.testing.expectError(error.ValidationFailed, B.decode(Limited, a, bad, .{}));
    }
}

test "conformance: missing required field is .required with the same path everywhere" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Empty = struct {};
    inline for (full_backends) |B| {
        const empty = try B.encodeAlloc(Empty, a, .{}, .{});
        const dr = try B.decodeResult(Limited, a, empty, .{ .validation = .none });
        try std.testing.expectEqual(serval.core.IssueCode.required, dr.invalid.issues[0].code);
        try std.testing.expectEqualStrings("name", dr.invalid.issues[0].path.segments[0].field);
        try std.testing.expectError(error.MissingRequiredField, B.decode(Limited, a, empty, .{}));
    }
}

test "conformance: unknown-field policies behave identically everywhere" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Wide = struct { name: []const u8, extra: i64 };
    const Narrow = struct { name: []const u8 };
    inline for (full_backends) |B| {
        const wide = try B.encodeAlloc(Wide, a, .{ .name = "ada", .extra = -5 }, .{});
        try std.testing.expectError(error.UnknownField, B.decode(Narrow, a, wide, .{}));
        const ignored = try B.decode(Narrow, a, wide, .{ .unknown_fields = .ignore });
        try std.testing.expectEqualStrings("ada", ignored.name);
        const dr = try B.decodeResult(Narrow, a, wide, .{ .unknown_fields = .collect });
        try std.testing.expectEqual(@as(usize, 1), dr.ok.unknown.len);
        try std.testing.expectEqual(@as(i128, -5), dr.ok.unknown[0].value.int);
    }
}

test "conformance: type mismatches and coercion agree everywhere" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Wire = struct { n: []const u8 };
    const Target = struct { n: u8 };
    inline for (full_backends) |B| {
        const doc = try B.encodeAlloc(Wire, a, .{ .n = "42" }, .{});
        // none: same mismatch error
        try std.testing.expectError(error.UnexpectedToken, B.decode(Target, a, doc, .{}));
        // safe: same coerced value
        const v = try B.decode(Target, a, doc, .{ .coercion = .safe });
        try std.testing.expectEqual(@as(u8, 42), v.n);
        // digit-separator rejection (SPEC D3) holds everywhere
        const sep = try B.encodeAlloc(Wire, a, .{ .n = "1_0" }, .{});
        try std.testing.expectError(error.UnexpectedToken, B.decode(Target, a, sep, .{ .coercion = .safe }));
    }
}

test "conformance: dynamic decodeValue agrees on Value shape across binary+json backends" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const P = struct { n: u64, s: []const u8, xs: []const i64 };
    const v = P{ .n = std.math.maxInt(u64), .s = "hi", .xs = &.{ 1, -2 } };
    inline for (full_backends) |B| {
        const doc = try B.encodeAlloc(P, a, v, .{});
        const dyn = try B.decodeValue(a, doc, .{});
        const obj = dyn.object;
        try std.testing.expectEqual(@as(i128, std.math.maxInt(u64)), obj[0].value.int);
        try std.testing.expectEqualStrings("hi", obj[1].value.string);
        try std.testing.expectEqual(@as(i128, -2), obj[2].value.array[1].int);
    }
}

// --- Capability descriptors (serval-xx5) ----------------------------------

test "capabilities: full backends declare the full set" {
    inline for (full_backends) |B| {
        const c = B.capabilities;
        try std.testing.expect(c.presence_tracking);
        try std.testing.expect(c.borrowed_mode);
        try std.testing.expect(c.coercion);
        try std.testing.expect(c.rename_metadata);
        try std.testing.expect(c.shape_issue_fidelity);
        try std.testing.expect(c.collect_unknown);
        try std.testing.expectEqual(serval.codec.UnionModeSupport.streaming, c.union_external);
        try std.testing.expectEqual(serval.codec.UnionModeSupport.streaming, c.union_adjacent);
        try std.testing.expectEqual(serval.codec.UnionModeSupport.buffered, c.union_internal);
        try std.testing.expectEqual(serval.codec.UnionModeSupport.buffered, c.union_untagged);
    }
}

test "capabilities: zon declares its gaps as flags, not prose" {
    const c = serval.zon.capabilities;
    try std.testing.expect(!c.presence_tracking);
    try std.testing.expect(!c.borrowed_mode);
    try std.testing.expect(!c.coercion);
    try std.testing.expect(!c.rename_metadata);
    try std.testing.expect(!c.shape_issue_fidelity);
    try std.testing.expect(!c.collect_unknown);
    try std.testing.expectEqual(serval.codec.UnionModeSupport.unsupported, c.union_external);
}

test "capabilities: consumers can comptime-branch on flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Wire = struct { n: []const u8 };
    const Target = struct { n: u8 };
    var coercion_capable: usize = 0;
    inline for (all_backends) |B| {
        if (comptime B.capabilities.coercion) {
            coercion_capable += 1;
            const doc = try B.encodeAlloc(Wire, a, .{ .n = "42" }, .{});
            const v = try B.decode(Target, a, doc, .{ .coercion = .safe });
            try std.testing.expectEqual(@as(u8, 42), v.n);
        }
    }
    try std.testing.expectEqual(@as(usize, 3), coercion_capable);
}

// --- Declared gaps stay declared -----------------------------------------

test "conformance: zon's shape-error folding is the documented gap, not silent drift" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Unknown field folds into InvalidSyntax on zon (SPEC §9 declared gap).
    const result = serval.zon.decode(Limited, arena.allocator(),
        \\.{ .name = "ada", .extra = 1 }
    , .{ .memory = .arena });
    try std.testing.expectError(error.InvalidSyntax, result);
}
