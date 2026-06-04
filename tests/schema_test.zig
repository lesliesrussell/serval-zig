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

test "all public decls compile" {
    std.testing.refAllDecls(serval);
    std.testing.refAllDecls(serval.core);
    std.testing.refAllDecls(serval.validate);
    std.testing.refAllDecls(serval.codec);
    std.testing.refAllDecls(serval.json);
    std.testing.refAllDecls(serval.derive);
    std.testing.refAllDecls(serval.testing);
}
