// serval-2si
const std = @import("std");
const serval = @import("serval");

const backends = .{ serval.json, serval.msgpack, serval.cbor };

const Limits = struct {
    cpu: u32 = 0,
    mem: u32 = 0,

    pub const serval = .{ .fields = .{ .cpu = .{ .max = 100 } } };
};

const Deployment = struct {
    name: []const u8,
    env: serval.core.Map([]const u8) = .{},
    services: serval.core.Map(Limits) = .{},
};

test "map: decodes arbitrary string keys across all backends" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dep = try serval.json.decode(Deployment, a,
        \\{"name":"web",
        \\ "env":{"PORT":"8080","LOG_LEVEL":"info"},
        \\ "services":{"api":{"cpu":50,"mem":256},"worker":{"cpu":25}}}
    , .{});
    try std.testing.expectEqual(@as(usize, 2), dep.env.entries.len);
    try std.testing.expectEqualStrings("8080", dep.env.get("PORT").?);
    try std.testing.expectEqual(@as(u32, 25), dep.services.get("worker").?.cpu);
    try std.testing.expectEqual(@as(u32, 0), dep.services.get("worker").?.mem); // default
    try std.testing.expect(dep.services.get("missing") == null);

    // entry order is data: preserved from input
    try std.testing.expectEqualStrings("PORT", dep.env.entries[0].key);
}

test "map: roundtrips through every backend, canonical included" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dep = Deployment{
        .name = "web",
        .env = .{ .entries = &.{
            .{ .key = "PORT", .value = "8080" },
            .{ .key = "MODE", .value = "fast" },
        } },
        .services = .{ .entries = &.{
            .{ .key = "api", .value = .{ .cpu = 50, .mem = 256 } },
        } },
    };
    inline for (backends) |B| {
        const wire = try B.encodeAlloc(Deployment, a, dep, .{});
        try std.testing.expectEqualDeep(dep, try B.decode(Deployment, a, wire, .{}));
        // canonical: struct keys sort; map entry order is data and survives
        const c1 = try B.encodeAlloc(Deployment, a, dep, .{ .canonical = true });
        const back = try B.decode(Deployment, a, c1, .{});
        try std.testing.expectEqualDeep(dep, back);
        const c2 = try B.encodeAlloc(Deployment, a, back, .{ .canonical = true });
        try std.testing.expectEqualSlices(u8, c1, c2);
    }
}

test "map: struct values validate with key path segments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const dr = try serval.json.decodeResult(Deployment, arena.allocator(),
        \\{"name":"web","services":{"api":{"cpu":150}}}
    , .{});
    try std.testing.expect(dr == .invalid);
    const issue = dr.invalid.issues[0];
    try std.testing.expectEqual(serval.core.IssueCode.max, issue.code);
    // path: .services["api"].cpu
    try std.testing.expectEqualStrings("services", issue.path.segments[0].field);
    try std.testing.expectEqualStrings("api", issue.path.segments[1].key);
    try std.testing.expectEqualStrings("cpu", issue.path.segments[2].field);
}

test "map: collection rules apply to entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const T = struct {
        env: serval.core.Map([]const u8) = .{},

        pub const serval_schema = .{ .fields = .{ .env = .{ .nonempty = true, .max_items = 2 } } };
    };
    var dr = try serval.json.decodeResult(T, arena.allocator(),
        \\{"env":{}}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.nonempty, dr.invalid.issues[0].code);

    dr = try serval.json.decodeResult(T, arena.allocator(),
        \\{"env":{"a":"1","b":"2","c":"3"}}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.max_items, dr.invalid.issues[0].code);
}

test "map: schema export emits additionalProperties subschema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const T = struct {
        env: serval.core.Map(u32) = .{},

        pub const serval_schema = .{ .fields = .{ .env = .{ .nonempty = true, .max_items = 8 } } };
    };
    const schema = try serval.schema_export.jsonSchema(T, arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, schema,
        \\"env":{"type":"object","additionalProperties":{"type":"integer","minimum":0,"maximum":4294967295},"minProperties":1,"maxProperties":8,"default":{}
    ) != null);
    _ = try serval.json.decodeValue(arena.allocator(), schema, .{});
}

test "map: dynamic walker validates map shapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const T = struct {
        env: serval.core.Map(u32) = .{},

        pub const serval_schema = .{ .fields = .{ .env = .{ .nonempty = true } } };
    };
    const report = try serval.validate.valueAgainstSchema(T, .{ .object = &.{
        .{ .name = "env", .value = .{ .object = &.{} } },
    } }, arena.allocator(), .{});
    try std.testing.expectEqual(serval.core.IssueCode.nonempty, report.issues[0].code);
}
