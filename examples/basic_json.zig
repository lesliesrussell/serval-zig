// serval-15q
//! Decode a JSON document into a typed struct.

const std = @import("std");
const serval = @import("serval");

const User = struct {
    id: u64,
    name: []const u8,
    age: ?u8 = null,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const user = try serval.json.decode(User, arena.allocator(),
        \\{"id":1,"name":"ada","age":36}
    , .{});

    std.debug.print("user {d}: {s} (age {?d})\n", .{ user.id, user.name, user.age });
}
