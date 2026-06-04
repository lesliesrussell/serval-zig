// serval-15q
//! Inspect a schema and run the validation pipeline over a config struct.

const std = @import("std");
const serval = @import("serval");

const Config = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    max_connections: u32 = 128,

    pub const serval = .{
        .fields = .{
            .host = .{ .min_len = 1 },
            .port = .{ .min = 1 },
        },
    };
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const S = serval.schemaOf(Config);
    std.debug.print("Config has {d} fields:\n", .{S.fields.len});
    for (S.fields) |f| {
        std.debug.print("  .{s} (optional={}, default={})\n", .{ f.name, f.is_optional, f.has_default });
    }

    const config = Config{};
    const report = try serval.validate.check(Config, &config, allocator, .{});
    defer allocator.free(report.issues);
    std.debug.print("valid: {}\n", .{report.ok()});
}
