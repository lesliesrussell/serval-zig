// serval-15q
const std = @import("std");
const serval = @import("serval");

const User = serval.testing.fixtures.User;

fn checkAlloc(comptime T: type, value: *const T) !serval.core.ValidationReport {
    return serval.validate.check(T, value, std.testing.allocator, .{});
}

test "check on valid value returns ok report" {
    const user = User{ .id = 1, .name = "ada" };
    const report = try checkAlloc(User, &user);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "context collects path-aware issues" {
    var ctx = serval.core.ValidateContext.init(std.testing.allocator);
    defer ctx.deinit();

    ctx.issue(.{
        .path = serval.core.Path.field("name"),
        .code = .min_len,
        .message = "name must not be empty",
    });

    const report = ctx.report();
    try std.testing.expect(!report.ok());
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.min_len, report.issues[0].code);
    try std.testing.expectEqualStrings("name", report.issues[0].path.segments[0].field);
}

test "empty report is ok" {
    const report = serval.core.ValidationReport{};
    try std.testing.expect(report.ok());
}

// serval-bfp
const Account = struct {
    name: []const u8,
    email: []const u8 = "a@b.io",
    age: ?u8 = null,
    score: i32 = 50,
    tags: []const u32 = &.{},

    pub const serval = .{
        .fields = .{
            .name = .{ .min_len = 2, .max_len = 8 },
            .email = .{ .email = true },
            .age = .{ .min = 13, .max = 120 },
            .score = .{ .gt = 0, .lt = 100 },
            .tags = .{ .min_items = 0, .max_items = 3, .unique = true },
        },
    };
};

test "scalar: min violation reported with path and code" {
    const acct = Account{ .name = "ada", .age = 9 };
    const report = try checkAlloc(Account, &acct);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.min, report.issues[0].code);
    try std.testing.expectEqualStrings("age", report.issues[0].path.segments[0].field);
    try std.testing.expectEqual(@as(?serval.core.Value, .{ .int = 13 }), report.issues[0].expected);
    try std.testing.expectEqual(@as(?serval.core.Value, .{ .int = 9 }), report.issues[0].actual);
}

test "scalar: gt/lt bounds" {
    const low = Account{ .name = "ada", .score = 0 };
    var report = try checkAlloc(Account, &low);
    try std.testing.expectEqual(serval.core.IssueCode.gt, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const high = Account{ .name = "ada", .score = 100 };
    report = try checkAlloc(Account, &high);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.lt, report.issues[0].code);
}

test "scalar: optional null skips constraints" {
    const acct = Account{ .name = "ada", .age = null };
    const report = try checkAlloc(Account, &acct);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "string: min_len and max_len" {
    const short = Account{ .name = "a" };
    var report = try checkAlloc(Account, &short);
    try std.testing.expectEqual(serval.core.IssueCode.min_len, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const long = Account{ .name = "verylongname" };
    report = try checkAlloc(Account, &long);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.max_len, report.issues[0].code);
}

test "string: email rule" {
    const bad = Account{ .name = "ada", .email = "not-an-email" };
    const report = try checkAlloc(Account, &bad);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.email, report.issues[0].code);
}

test "collection: max_items and unique" {
    const many = Account{ .name = "ada", .tags = &.{ 1, 2, 3, 4 } };
    var report = try checkAlloc(Account, &many);
    try std.testing.expectEqual(serval.core.IssueCode.max_items, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const dup = Account{ .name = "ada", .tags = &.{ 1, 2, 1 } };
    report = try checkAlloc(Account, &dup);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.unique, report.issues[0].code);
}

test "multiple violations all reported" {
    const acct = Account{ .name = "a", .email = "nope", .age = 5 };
    const report = try checkAlloc(Account, &acct);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), report.issues.len);
}

// serval-bcz
const Coded = struct {
    code: []const u8,

    pub const serval = .{
        .fields = .{ .code = .{ .pattern = "^[A-Z]+-[0-9]+$" } },
    };
};

test "pattern: matching string passes" {
    const v = Coded{ .code = "ABC-123" };
    const report = try checkAlloc(Coded, &v);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "pattern: non-matching string reported" {
    const v = Coded{ .code = "abc" };
    const report = try checkAlloc(Coded, &v);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.pattern, report.issues[0].code);
    try std.testing.expectEqualStrings("code", report.issues[0].path.segments[0].field);
}

// serval-yus: invalid .pattern regexes are now compile errors, not
// runtime issues — uncompilable patterns can't ship.

// serval-yus
const Reading = struct {
    temp: f64,
    ratio: f32 = 0.5,

    pub const serval = .{
        .fields = .{
            .temp = .{ .min = -40, .max = 125 },
            .ratio = .{ .gt = 0, .lt = 1 },
        },
    };
};

test "float: integral bounds applied" {
    const hot = Reading{ .temp = 200 };
    var report = try checkAlloc(Reading, &hot);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.max, report.issues[0].code);
    try std.testing.expectEqual(@as(f64, 200), report.issues[0].actual.?.float);
    report.deinit(std.testing.allocator);

    const edge = Reading{ .temp = 20, .ratio = 1 };
    report = try checkAlloc(Reading, &edge);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.lt, report.issues[0].code);
}

test "float: in-range value passes" {
    const ok_val = Reading{ .temp = 21.5 };
    const report = try checkAlloc(Reading, &ok_val);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

// serval-l3p
fn vObj(comptime fields: []const serval.core.FieldValue) serval.core.Value {
    return .{ .object = fields };
}

test "valueAgainstSchema: valid object passes" {
    const v = vObj(&.{
        .{ .name = "name", .value = .{ .string = "ada" } },
        .{ .name = "age", .value = .{ .int = 30 } },
    });
    const Person = struct {
        name: []const u8,
        age: ?u8 = null,

        pub const serval = .{ .fields = .{ .name = .{ .min_len = 2 }, .age = .{ .max = 120 } } };
    };
    const report = try serval.validate.valueAgainstSchema(Person, v, std.testing.allocator, .{});
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "valueAgainstSchema: type mismatch, missing, unknown, constraint" {
    const Person = struct {
        name: []const u8,
        age: u8,

        pub const serval = .{ .fields = .{ .name = .{ .min_len = 2 } } };
    };

    // wrong type for age
    var report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "name", .value = .{ .string = "ada" } },
        .{ .name = "age", .value = .{ .string = "old" } },
    }), std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.invalid_type, report.issues[0].code);
    try std.testing.expectEqualStrings("age", report.issues[0].path.segments[0].field);
    report.deinit(std.testing.allocator);

    // missing required age
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "name", .value = .{ .string = "ada" } },
    }), std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.required, report.issues[0].code);
    report.deinit(std.testing.allocator);

    // unknown field
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "name", .value = .{ .string = "ada" } },
        .{ .name = "age", .value = .{ .int = 30 } },
        .{ .name = "shoe", .value = .{ .int = 44 } },
    }), std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.unknown_field, report.issues[0].code);
    report.deinit(std.testing.allocator);

    // constraint violation through the dynamic path
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "name", .value = .{ .string = "a" } },
        .{ .name = "age", .value = .{ .int = 30 } },
    }), std.testing.allocator, .{});
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.min_len, report.issues[0].code);
}

test "valueAgainstSchema: nested, arrays, enums, wire names" {
    const Doc = struct {
        level: enum { low, high },
        items: []const i64,
        inner: struct { x: i32 },
        user_id: u64,

        pub const serval = .{
            .rename_all = .camel_case,
            .fields = .{ .items = .{ .max_items = 2 } },
        };
    };

    // valid shape uses camelCase wire names
    var report = try serval.validate.valueAgainstSchema(Doc, vObj(&.{
        .{ .name = "level", .value = .{ .string = "high" } },
        .{ .name = "items", .value = .{ .array = &.{.{ .int = 1 }} } },
        .{ .name = "inner", .value = vObj(&.{.{ .name = "x", .value = .{ .int = -2 } }}) },
        .{ .name = "userId", .value = .{ .int = 9 } },
    }), std.testing.allocator, .{});
    try std.testing.expect(report.ok());
    report.deinit(std.testing.allocator);

    // bad enum tag + too many items + nested type error
    report = try serval.validate.valueAgainstSchema(Doc, vObj(&.{
        .{ .name = "level", .value = .{ .string = "medium" } },
        .{ .name = "items", .value = .{ .array = &.{ .{ .int = 1 }, .{ .int = 2 }, .{ .int = 3 } } } },
        .{ .name = "inner", .value = vObj(&.{.{ .name = "x", .value = .{ .bool = true } }}) },
        .{ .name = "userId", .value = .{ .int = 9 } },
    }), std.testing.allocator, .{});
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), report.issues.len);
}

// serval-4tr
test "valueAgainstSchema honors coercion mode" {
    const Person = struct {
        age: u8,

        pub const serval = .{ .fields = .{ .age = .{ .min = 13 } } };
    };
    const dyn = vObj(&.{
        .{ .name = "age", .value = .{ .string = "42" } },
    });

    // none: type mismatch
    var report = try serval.validate.valueAgainstSchema(Person, dyn, std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.invalid_type, report.issues[0].code);
    report.deinit(std.testing.allocator);

    // safe: coerces, then constraints run on the coerced value
    report = try serval.validate.valueAgainstSchema(Person, dyn, std.testing.allocator, .{ .coercion = .safe });
    try std.testing.expect(report.ok());
    report.deinit(std.testing.allocator);

    // safe + constraint violation on coerced value
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "age", .value = .{ .string = "9" } },
    }), std.testing.allocator, .{ .coercion = .safe });
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.min, report.issues[0].code);
}

// serval-elw
const Plan = struct {
    tier: u8 = 1,
    region: []const u8 = "us",
    tags: []const u32 = &.{0},

    pub const serval = .{
        .fields = .{
            .tier = .{ .one_of = &.{ 1, 2, 3 } },
            .region = .{ .one_of_str = &.{ "us", "eu" } },
            .tags = .{ .nonempty = true },
        },
    };
};

test "one_of: scalar and string membership" {
    const ok_plan = Plan{ .tier = 2, .region = "eu" };
    var report = try checkAlloc(Plan, &ok_plan);
    try std.testing.expect(report.ok());
    report.deinit(std.testing.allocator);

    const bad_tier = Plan{ .tier = 5 };
    report = try checkAlloc(Plan, &bad_tier);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.one_of, report.issues[0].code);
    try std.testing.expectEqualStrings("tier", report.issues[0].path.segments[0].field);
    report.deinit(std.testing.allocator);

    const bad_region = Plan{ .region = "jp" };
    report = try checkAlloc(Plan, &bad_region);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.one_of, report.issues[0].code);
}

test "nonempty: strings and collections" {
    const NonEmpty = struct {
        name: []const u8 = "x",
        items: []const i64 = &.{0},

        pub const serval = .{
            .fields = .{
                .name = .{ .nonempty = true },
                .items = .{ .nonempty = true },
            },
        };
    };

    const empty_str = NonEmpty{ .name = "" };
    var report = try checkAlloc(NonEmpty, &empty_str);
    try std.testing.expectEqual(serval.core.IssueCode.nonempty, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const empty_items = NonEmpty{ .items = &.{} };
    report = try checkAlloc(NonEmpty, &empty_items);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.nonempty, report.issues[0].code);
}

test "one_of and nonempty on the dynamic path" {
    var report = try serval.validate.valueAgainstSchema(Plan, vObj(&.{
        .{ .name = "tier", .value = .{ .int = 9 } },
        .{ .name = "region", .value = .{ .string = "eu" } },
        .{ .name = "tags", .value = .{ .array = &.{.{ .int = 1 }} } },
    }), std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.one_of, report.issues[0].code);
    report.deinit(std.testing.allocator);

    report = try serval.validate.valueAgainstSchema(Plan, vObj(&.{
        .{ .name = "tier", .value = .{ .int = 1 } },
        .{ .name = "region", .value = .{ .string = "us" } },
        .{ .name = "tags", .value = .{ .array = &.{} } },
    }), std.testing.allocator, .{});
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.nonempty, report.issues[0].code);
}

// serval-sru
const Address = struct {
    zip: []const u8 = "12345",

    pub const serval = .{ .fields = .{ .zip = .{ .min_len = 5 } } };
};

const Customer = struct {
    name: []const u8 = "ok",
    home: Address = .{},
    addresses: []const Address = &.{},
};

test "nested paths: typed check recurses into nested structs" {
    const c = Customer{ .home = .{ .zip = "1" } };
    const report = try checkAlloc(Customer, &c);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    const segs = report.issues[0].path.segments;
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("home", segs[0].field);
    try std.testing.expectEqualStrings("zip", segs[1].field);
}

test "nested paths: slice-of-struct elements carry index segments" {
    const c = Customer{ .addresses = &.{ .{}, .{ .zip = "9" } } };
    const report = try checkAlloc(Customer, &c);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    const segs = report.issues[0].path.segments;
    try std.testing.expectEqual(@as(usize, 3), segs.len);
    try std.testing.expectEqualStrings("addresses", segs[0].field);
    try std.testing.expectEqual(@as(usize, 1), segs[1].index);
    try std.testing.expectEqualStrings("zip", segs[2].field);
}

test "nested paths: path formats to dotted string" {
    const c = Customer{ .addresses = &.{.{ .zip = "9" }} };
    const report = try checkAlloc(Customer, &c);
    defer report.deinit(std.testing.allocator);
    const rendered = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{report.issues[0].path});
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(".addresses[0].zip", rendered);
}

test "nested paths: dynamic walker carries nested paths" {
    const report = try serval.validate.valueAgainstSchema(Customer, vObj(&.{
        .{ .name = "home", .value = vObj(&.{.{ .name = "zip", .value = .{ .string = "1" } }}) },
    }), std.testing.allocator, .{});
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    const segs = report.issues[0].path.segments;
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("home", segs[0].field);
    try std.testing.expectEqualStrings("zip", segs[1].field);
}

// serval-m9b
test "unique: duplicate strings caught by content, not pointer identity" {
    const T = struct {
        tags: []const []const u8 = &.{},

        pub const serval = .{ .fields = .{ .tags = .{ .unique = true } } };
    };
    // Distinct allocations, identical content — must be a duplicate.
    var a = [_]u8{ 'd', 'u', 'p' };
    var b = [_]u8{ 'd', 'u', 'p' };
    const v = T{ .tags = &.{ &a, &b } };
    var report = try checkAlloc(T, &v);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.unique, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const ok_v = T{ .tags = &.{ "one", "two" } };
    report = try checkAlloc(T, &ok_v);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "unique: structs compared deeply, including their string fields" {
    const Item = struct { id: u32, name: []const u8 };
    const T = struct {
        items: []const Item = &.{},

        pub const serval = .{ .fields = .{ .items = .{ .unique = true } } };
    };
    var n1 = [_]u8{'x'};
    var n2 = [_]u8{'x'};
    const dup = T{ .items = &.{ .{ .id = 1, .name = &n1 }, .{ .id = 1, .name = &n2 } } };
    var report = try checkAlloc(T, &dup);
    try std.testing.expectEqual(serval.core.IssueCode.unique, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const distinct = T{ .items = &.{ .{ .id = 1, .name = "x" }, .{ .id = 2, .name = "x" } } };
    report = try checkAlloc(T, &distinct);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "unique: float equality per spec §5 — NaN never duplicates, -0.0 == 0.0 does" {
    const T = struct {
        xs: []const f64 = &.{},

        pub const serval = .{ .fields = .{ .xs = .{ .unique = true } } };
    };
    const nans = T{ .xs = &.{ std.math.nan(f64), std.math.nan(f64) } };
    var report = try checkAlloc(T, &nans);
    try std.testing.expect(report.ok());
    report.deinit(std.testing.allocator);

    const zeros = T{ .xs = &.{ -0.0, 0.0 } };
    report = try checkAlloc(T, &zeros);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqual(serval.core.IssueCode.unique, report.issues[0].code);
}

test "unique: dynamic path adopts the same definition, Value-tag strict" {
    const T = struct {
        tags: []const []const u8 = &.{},

        pub const serval = .{ .fields = .{ .tags = .{ .unique = true } } };
    };
    var report = try serval.validate.valueAgainstSchema(T, vObj(&.{
        .{ .name = "tags", .value = .{ .array = &.{ .{ .string = "dup" }, .{ .string = "dup" } } } },
    }), std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.unique, report.issues[0].code);
    report.deinit(std.testing.allocator);

    // int 1 and float 1.0 are different Value variants — not duplicates.
    const N = struct {
        ns: []const f64 = &.{},

        pub const serval = .{ .fields = .{ .ns = .{ .unique = true } } };
    };
    report = try serval.validate.valueAgainstSchema(N, vObj(&.{
        .{ .name = "ns", .value = .{ .array = &.{ .{ .int = 1 }, .{ .float = 1.0 } } } },
    }), std.testing.allocator, .{});
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "pattern: full-match option" {
    const T = struct {
        code: []const u8 = "",

        pub const serval = .{ .fields = .{ .code = .{ .pattern = "a+", .pattern_full = true } } };
    };
    const partial = T{ .code = "baaa" }; // search would match; full must not
    var report = try checkAlloc(T, &partial);
    try std.testing.expectEqual(serval.core.IssueCode.pattern, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const exact = T{ .code = "aaa" };
    report = try checkAlloc(T, &exact);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

// serval-bmf
fn noShouting(ctx: *serval.core.ValidateContext, name: *const []const u8) void {
    for (name.*) |c| {
        if (std.ascii.isLower(c)) return;
    }
    if (name.len > 0) ctx.issue(.{ .path = .root, .code = .custom, .message = "no shouting" });
}

const Polite = struct {
    name: []const u8 = "ok",

    pub const serval = .{
        .fields = .{ .name = .{ .min_len = 1, .validator = noShouting } },
    };
};

test "field validator: invoked alongside built-in rules with field path" {
    const loud = Polite{ .name = "HEY" };
    var report = try checkAlloc(Polite, &loud);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.custom, report.issues[0].code);
    try std.testing.expectEqualStrings("name", report.issues[0].path.segments[0].field);
    report.deinit(std.testing.allocator);

    const fine = Polite{ .name = "Hey" };
    report = try checkAlloc(Polite, &fine);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}

test "field validator: runs in nested structs with full paths" {
    const Outer = struct { who: Polite = .{} };
    const v = Outer{ .who = .{ .name = "LOUD" } };
    const report = try checkAlloc(Outer, &v);
    defer report.deinit(std.testing.allocator);
    const segs = report.issues[0].path.segments;
    try std.testing.expectEqual(@as(usize, 2), segs.len);
    try std.testing.expectEqualStrings("who", segs[0].field);
    try std.testing.expectEqualStrings("name", segs[1].field);
}

test "field validator: decode path sees the transformed value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const T = struct {
        name: []const u8,

        pub const serval = .{
            .fields = .{ .name = .{ .trim = true, .lowercase = true, .validator = noShouting } },
        };
    };
    // raw "  HEY  " would fail; lowercase transform runs first.
    const v = try serval.json.decode(T, arena.allocator(),
        \\{"name":"  HEY  "}
    , .{});
    try std.testing.expectEqualStrings("hey", v.name);
}

// serval-3g8
test "error UX: messages carry their limits" {
    const T = struct {
        age: u8 = 50,
        name: []const u8 = "okay",

        pub const serval = .{ .fields = .{
            .age = .{ .min = 13 },
            .name = .{ .min_len = 3 },
        } };
    };
    const v = T{ .age = 9, .name = "x" };
    const report = try checkAlloc(T, &v);
    defer report.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("below minimum 13", report.issues[0].message);
    try std.testing.expectEqualStrings("shorter than minimum length 3", report.issues[1].message);
}

test "error UX: report renders grouped, path-first, with expected/actual" {
    const Address2 = struct {
        zip: []const u8 = "12345",

        pub const serval = .{ .fields = .{ .zip = .{ .min_len = 5 } } };
    };
    const Customer2 = struct {
        age: u8 = 30,
        addresses: []const Address2 = &.{},

        pub const serval = .{ .fields = .{ .age = .{ .min = 13 } } };
    };
    const v = Customer2{ .age = 9, .addresses = &.{ .{}, .{ .zip = "1" } } };
    const report = try checkAlloc(Customer2, &v);
    defer report.deinit(std.testing.allocator);

    var buf: [512]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try report.render(&w);
    try std.testing.expectEqualStrings(
        \\validation failed (2 issues):
        \\  .age: below minimum 13 (expected 13, actual 9)
        \\  .addresses[1].zip: shorter than minimum length 5 (expected 5, actual 1)
        \\
    , w.buffered());
}

// serval-bfp
const Minor = struct {
    age: u8,
    guardian_email: []const u8 = "",

    pub fn servalValidate(ctx: *serval.core.ValidateContext, self: *const Minor) void {
        if (self.age < 18 and self.guardian_email.len == 0) {
            ctx.issue(.{
                .path = serval.core.Path.field("guardian_email"),
                .code = .required_when,
                .message = "guardian_email is required for minors",
            });
        }
    }
};

test "struct-level custom validator invoked" {
    const kid = Minor{ .age = 12 };
    var report = try checkAlloc(Minor, &kid);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.required_when, report.issues[0].code);
    report.deinit(std.testing.allocator);

    const adult = Minor{ .age = 30 };
    report = try checkAlloc(Minor, &adult);
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.ok());
}
