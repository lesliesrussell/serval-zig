// serval-dfo
//! Pinning tests for docs/SPEC.md. Each test enforces a frozen semantic;
//! the spec section is named in the test name. If one of these breaks,
//! either the change is a bug or the spec needs a deliberate revision.

const std = @import("std");
const serval = @import("serval");

fn arenaAlloc(arena: *std.heap.ArenaAllocator) std.mem.Allocator {
    return arena.allocator();
}

// --- §2 Value contract -------------------------------------------------

test "spec §2: Value.int is i64 — u64 beyond maxInt(i64) is a loss point on the dynamic path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Big = struct { n: u64 };
    const encoded = try serval.msgpack.encodeAlloc(Big, arena.allocator(), .{ .n = std.math.maxInt(u64) }, .{});
    // Typed path: lossless.
    const typed = try serval.msgpack.decode(Big, arena.allocator(), encoded, .{});
    try std.testing.expectEqual(std.math.maxInt(u64), typed.n);
    // Dynamic path: Overflow (DECISION D1 may widen Value.int to i128).
    try std.testing.expectError(error.Overflow, serval.msgpack.decodeValue(arena.allocator(), encoded, .{}));
}

// --- §4 Coercion edge matrix --------------------------------------------

const IntField = struct { n: u8 = 0 };
const FloatField = struct { x: f64 = 0 };

test "spec §4: numeric string coercion accepts an optional sign, rejects whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const signed = try serval.json.decode(IntField, a,
        \\{"n":"+42"}
    , .{ .coercion = .safe });
    try std.testing.expectEqual(@as(u8, 42), signed.n);

    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(IntField, a,
        \\{"n":" 42"}
    , .{ .coercion = .safe }));
}

test "spec §4: scientific notation never coerces from STRINGS into ints, any mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(IntField, a,
        \\{"n":"1e2"}
    , .{ .coercion = .safe }));
    // String coercion is exact-int only — even aggressive does not route
    // through float parsing. (Asymmetry with number tokens below.)
    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(IntField, a,
        \\{"n":"1e2"}
    , .{ .coercion = .aggressive }));
}

test "spec §4: scientific-notation NUMBER tokens reach ints only via aggressive truncation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectError(error.UnexpectedToken, serval.json.decode(IntField, a,
        \\{"n":1e2}
    , .{ .coercion = .safe }));
    const v = try serval.json.decode(IntField, a,
        \\{"n":1e2}
    , .{ .coercion = .aggressive });
    try std.testing.expectEqual(@as(u8, 100), v.n);
}

test "spec §4: Zig digit separators currently leak into string-to-int coercion (DECISION D3)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v = try serval.json.decode(IntField, arena.allocator(),
        \\{"n":"1_0"}
    , .{ .coercion = .safe });
    try std.testing.expectEqual(@as(u8, 10), v.n);
}

test "spec §4: string-to-float coercion currently accepts inf/nan spellings (DECISION D2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const sci = try serval.json.decode(FloatField, a,
        \\{"x":"1e2"}
    , .{ .coercion = .safe });
    try std.testing.expectEqual(@as(f64, 100), sci.x);

    const inf = try serval.json.decode(FloatField, a,
        \\{"x":"inf"}
    , .{ .coercion = .safe });
    try std.testing.expect(std.math.isInf(inf.x));
}

test "spec §4: float-to-int truncates toward zero; non-finite and out-of-range are Overflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const I = struct { n: i32 = 0 };
    const neg = try serval.json.decode(I, a,
        \\{"n":-41.9}
    , .{ .coercion = .aggressive });
    try std.testing.expectEqual(@as(i32, -41), neg.n);

    // DECISION D4: NaN/Inf currently map to Overflow, not a distinct error.
    const nan_doc = [_]u8{ 0x81, 0xa1, 'n', 0xcb, 0x7f, 0xf8, 0, 0, 0, 0, 0, 0 }; // msgpack {n: f64 NaN}
    try std.testing.expectError(error.Overflow, serval.msgpack.decode(I, a, &nan_doc, .{ .coercion = .aggressive }));
}

// --- §6 Presence --------------------------------------------------------

test "spec §6: presence means present-in-input — defaulted fields are absent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const P = struct {
        name: []const u8,
        nickname: []const u8 = "anon",

        pub fn servalValidate(ctx: *serval.core.ValidateContext, self: *const @This()) void {
            _ = self;
            // nickname was defaulted, not supplied: must read as absent.
            if (ctx.has("nickname")) {
                ctx.issue(.{ .path = .root, .code = .custom, .message = "defaulted field reported present" });
            }
        }
    };
    const dr = try serval.json.decodeResult(P, arena.allocator(),
        \\{"name":"ada"}
    , .{});
    try std.testing.expect(dr == .ok);
}

test "spec §6: presence tracking is disabled when validation is .none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // With validation off, the report path never runs — pinned by the
    // zero-allocation guarantee tests in json_test/msgpack_test/cbor_test.
    const P = struct { name: []const u8 };
    const v = try serval.json.decode(P, arena.allocator(),
        \\{"name":"ada"}
    , .{ .validation = .none });
    try std.testing.expectEqualStrings("ada", v.name);
}

// --- §8 Pipeline phases -------------------------------------------------

test "spec §8: typed check() runs constraints only — no coercion, no transforms" {
    const T = struct {
        name: []const u8,

        pub const serval = .{ .fields = .{ .name = .{ .trim = true, .min_len = 3 } } };
    };
    // The untrimmed value is what check() sees: "  x  " has len 5, passes
    // min_len even though its decoded form ("x") would fail.
    const v = T{ .name = "  x  " };
    const report = try serval.validate.check(T, &v, std.testing.allocator, .{});
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "spec §8: decode applies transforms before constraints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const T = struct {
        name: []const u8,

        pub const serval = .{ .fields = .{ .name = .{ .trim = true, .min_len = 3 } } };
    };
    // Same input through decode: trimmed to "x", min_len now fails.
    const result = serval.json.decode(T, arena.allocator(),
        \\{"name":"  x  "}
    , .{});
    try std.testing.expectError(error.ValidationFailed, result);
}
