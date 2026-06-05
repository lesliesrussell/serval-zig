// serval-15q
const std = @import("std");
const serval = @import("serval");

const User = serval.testing.fixtures.User;

test "schema reflects struct fields" {
    const S = serval.schemaOf(User);
    try std.testing.expectEqual(@as(usize, 4), S.fields.len);
    try std.testing.expectEqualStrings("id", S.fields[0].name);
    try std.testing.expectEqualStrings("name", S.fields[1].name);
    try std.testing.expect(!S.fields[0].has_default);
    try std.testing.expect(S.fields[2].has_default); // email = ""
    try std.testing.expect(S.fields[3].is_optional); // age: ?u8
    try std.testing.expect(S.fields[3].has_default);
}

test "schema of non-struct has no fields" {
    const S = serval.schemaOf(u32);
    try std.testing.expectEqual(@as(usize, 0), S.fields.len);
}

test "kindOf classifies types" {
    const k = serval.core.type_info.kindOf;
    try std.testing.expectEqual(.int, k(u8));
    try std.testing.expectEqual(.float, k(f64));
    try std.testing.expectEqual(.optional, k(?u8));
    try std.testing.expectEqual(.slice, k([]const u8));
    try std.testing.expectEqual(.@"struct", k(User));
}

test "metadata detection" {
    const Tagged = struct {
        x: u32,
        pub const serval_meta_placeholder = {};
        pub const serval = .{};
    };
    try std.testing.expect(serval.derive.inspect.hasMetadata(Tagged));
    try std.testing.expect(!serval.derive.inspect.hasMetadata(User));
}

test "metadata: field constraints extracted" {
    const Account = struct {
        name: []const u8,
        age: ?u8 = null,

        pub const serval = .{
            .fields = .{
                .name = .{ .min_len = 1, .max_len = 100 },
                .age = .{ .min = 13, .max = 120 },
            },
        };
    };
    const S = serval.schemaOf(Account);
    try std.testing.expectEqual(@as(?usize, 1), S.fields[0].meta.min_len);
    try std.testing.expectEqual(@as(?usize, 100), S.fields[0].meta.max_len);
    try std.testing.expectEqual(@as(?i64, 13), S.fields[1].meta.min);
    try std.testing.expectEqual(@as(?i64, 120), S.fields[1].meta.max);
}

test "metadata: rename_all produces wire names" {
    const Msg = struct {
        user_id: u64,
        display_name: []const u8,

        pub const serval = .{ .rename_all = .camel_case };
    };
    const S = serval.schemaOf(Msg);
    try std.testing.expectEqualStrings("userId", S.fields[0].wire_name);
    try std.testing.expectEqualStrings("displayName", S.fields[1].wire_name);
}

test "metadata: explicit rename wins over rename_all" {
    const Msg = struct {
        user_id: u64,

        pub const serval = .{
            .rename_all = .camel_case,
            .fields = .{ .user_id = .{ .rename = "uid" } },
        };
    };
    try std.testing.expectEqualStrings("uid", serval.schemaOf(Msg).fields[0].wire_name);
}

test "metadata: wire name defaults to field name" {
    const S = serval.schemaOf(User);
    try std.testing.expectEqualStrings("id", S.fields[0].wire_name);
}

test "metadata: type options extracted" {
    const Blob = struct {
        data: []const u8,

        pub const serval = .{ .bytes_policy = .bytes, .enum_tagging = .value };
    };
    const S = serval.schemaOf(Blob);
    try std.testing.expectEqual(serval.core.attributes.BytesPolicy.bytes, S.options.bytes_policy);
    try std.testing.expectEqual(serval.core.attributes.EnumTagging.value, S.options.enum_tagging);
}

test "naming conversions" {
    const conv = serval.core.naming.convert;
    try std.testing.expectEqualStrings("foo_bar", conv(.none, "foo_bar"));
    try std.testing.expectEqualStrings("foo_bar", conv(.snake_case, "foo_bar"));
    try std.testing.expectEqualStrings("fooBar", conv(.camel_case, "foo_bar"));
    try std.testing.expectEqualStrings("FooBar", conv(.pascal_case, "foo_bar"));
    try std.testing.expectEqualStrings("foo-bar", conv(.kebab_case, "foo_bar"));
    try std.testing.expectEqualStrings("aBC", conv(.camel_case, "a_b_c"));
}

test "all public decls compile" {
    std.testing.refAllDecls(serval);
    std.testing.refAllDecls(serval.core);
    std.testing.refAllDecls(serval.validate);
    std.testing.refAllDecls(serval.codec);
    std.testing.refAllDecls(serval.json);
    std.testing.refAllDecls(serval.derive);
    std.testing.refAllDecls(serval.testing);
}
