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
    defer std.testing.allocator.free(report.issues);
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
    defer std.testing.allocator.free(report.issues);
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
    std.testing.allocator.free(report.issues);

    const high = Account{ .name = "ada", .score = 100 };
    report = try checkAlloc(Account, &high);
    defer std.testing.allocator.free(report.issues);
    try std.testing.expectEqual(serval.core.IssueCode.lt, report.issues[0].code);
}

test "scalar: optional null skips constraints" {
    const acct = Account{ .name = "ada", .age = null };
    const report = try checkAlloc(Account, &acct);
    defer std.testing.allocator.free(report.issues);
    try std.testing.expect(report.ok());
}

test "string: min_len and max_len" {
    const short = Account{ .name = "a" };
    var report = try checkAlloc(Account, &short);
    try std.testing.expectEqual(serval.core.IssueCode.min_len, report.issues[0].code);
    std.testing.allocator.free(report.issues);

    const long = Account{ .name = "verylongname" };
    report = try checkAlloc(Account, &long);
    defer std.testing.allocator.free(report.issues);
    try std.testing.expectEqual(serval.core.IssueCode.max_len, report.issues[0].code);
}

test "string: email rule" {
    const bad = Account{ .name = "ada", .email = "not-an-email" };
    const report = try checkAlloc(Account, &bad);
    defer std.testing.allocator.free(report.issues);
    try std.testing.expectEqual(@as(usize, 1), report.issues.len);
    try std.testing.expectEqual(serval.core.IssueCode.email, report.issues[0].code);
}

test "collection: max_items and unique" {
    const many = Account{ .name = "ada", .tags = &.{ 1, 2, 3, 4 } };
    var report = try checkAlloc(Account, &many);
    try std.testing.expectEqual(serval.core.IssueCode.max_items, report.issues[0].code);
    std.testing.allocator.free(report.issues);

    const dup = Account{ .name = "ada", .tags = &.{ 1, 2, 1 } };
    report = try checkAlloc(Account, &dup);
    defer std.testing.allocator.free(report.issues);
    try std.testing.expectEqual(serval.core.IssueCode.unique, report.issues[0].code);
}

test "multiple violations all reported" {
    const acct = Account{ .name = "a", .email = "nope", .age = 5 };
    const report = try checkAlloc(Account, &acct);
    defer std.testing.allocator.free(report.issues);
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
    defer std.testing.allocator.free(report.issues);
    try std.testing.expect(report.ok());
}

test "pattern: non-matching string reported" {
    const v = Coded{ .code = "abc" };
    const report = try checkAlloc(Coded, &v);
    defer std.testing.allocator.free(report.issues);
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
    std.testing.allocator.free(report.issues);

    const edge = Reading{ .temp = 20, .ratio = 1 };
    report = try checkAlloc(Reading, &edge);
    defer std.testing.allocator.free(report.issues);
    try std.testing.expectEqual(serval.core.IssueCode.lt, report.issues[0].code);
}

test "float: in-range value passes" {
    const ok_val = Reading{ .temp = 21.5 };
    const report = try checkAlloc(Reading, &ok_val);
    defer std.testing.allocator.free(report.issues);
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
    defer std.testing.allocator.free(report.issues);
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
    std.testing.allocator.free(report.issues);

    // missing required age
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "name", .value = .{ .string = "ada" } },
    }), std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.required, report.issues[0].code);
    std.testing.allocator.free(report.issues);

    // unknown field
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "name", .value = .{ .string = "ada" } },
        .{ .name = "age", .value = .{ .int = 30 } },
        .{ .name = "shoe", .value = .{ .int = 44 } },
    }), std.testing.allocator, .{});
    try std.testing.expectEqual(serval.core.IssueCode.unknown_field, report.issues[0].code);
    std.testing.allocator.free(report.issues);

    // constraint violation through the dynamic path
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "name", .value = .{ .string = "a" } },
        .{ .name = "age", .value = .{ .int = 30 } },
    }), std.testing.allocator, .{});
    defer std.testing.allocator.free(report.issues);
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
    std.testing.allocator.free(report.issues);

    // bad enum tag + too many items + nested type error
    report = try serval.validate.valueAgainstSchema(Doc, vObj(&.{
        .{ .name = "level", .value = .{ .string = "medium" } },
        .{ .name = "items", .value = .{ .array = &.{ .{ .int = 1 }, .{ .int = 2 }, .{ .int = 3 } } } },
        .{ .name = "inner", .value = vObj(&.{.{ .name = "x", .value = .{ .bool = true } }}) },
        .{ .name = "userId", .value = .{ .int = 9 } },
    }), std.testing.allocator, .{});
    defer std.testing.allocator.free(report.issues);
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
    std.testing.allocator.free(report.issues);

    // safe: coerces, then constraints run on the coerced value
    report = try serval.validate.valueAgainstSchema(Person, dyn, std.testing.allocator, .{ .coercion = .safe });
    try std.testing.expect(report.ok());
    std.testing.allocator.free(report.issues);

    // safe + constraint violation on coerced value
    report = try serval.validate.valueAgainstSchema(Person, vObj(&.{
        .{ .name = "age", .value = .{ .string = "9" } },
    }), std.testing.allocator, .{ .coercion = .safe });
    defer std.testing.allocator.free(report.issues);
    try std.testing.expectEqual(serval.core.IssueCode.min, report.issues[0].code);
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
    std.testing.allocator.free(report.issues);

    const adult = Minor{ .age = 30 };
    report = try checkAlloc(Minor, &adult);
    defer std.testing.allocator.free(report.issues);
    try std.testing.expect(report.ok());
}
