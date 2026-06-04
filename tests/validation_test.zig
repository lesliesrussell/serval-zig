// serval-15q
const std = @import("std");
const serval = @import("serval");

const User = serval.testing.fixtures.User;

test "check on valid value returns ok report" {
    const user = User{ .id = 1, .name = "ada" };
    const report = try serval.validate.check(User, &user, std.testing.allocator, .{});
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
