// serval-9ov
const std = @import("std");
const serval = @import("serval");

const prefix =
    \\{"$schema":"https://json-schema.org/draft/2020-12/schema",
;

fn expectSchema(comptime T: type, expected_body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const out = try serval.schema_export.jsonSchema(T, arena.allocator());
    const expected = try std.mem.concat(arena.allocator(), u8, &.{ prefix, expected_body });
    try std.testing.expectEqualStrings(expected, out);

    // every emitted schema must itself be well-formed JSON
    _ = try serval.json.decodeValue(arena.allocator(), out, .{});
}

test "json schema: flat struct with constraints, optionals, defaults" {
    const User = struct {
        id: u32,
        name: []const u8,
        age: ?u8 = null,

        pub const serval = .{ .fields = .{ .name = .{ .min_len = 1, .max_len = 10 } } };
    };
    try expectSchema(User,
        \\"type":"object","properties":{"id":{"type":"integer","minimum":0,"maximum":4294967295},"name":{"type":"string","minLength":1,"maxLength":10},"age":{"anyOf":[{"type":"integer","minimum":0,"maximum":255},{"type":"null"}],"default":null}},"required":["id","name"],"additionalProperties":false}
    );
}

test "json schema: enums, arrays, scalar membership, renames" {
    const Doc = struct {
        level_name: enum { low, high } = .low,
        tags: []const i64 = &.{},
        tier: u8 = 1,

        pub const serval = .{
            .rename_all = .camel_case,
            .fields = .{
                .tags = .{ .max_items = 3, .unique = true, .nonempty = true },
                .tier = .{ .one_of = &.{ 1, 2, 3 } },
            },
        };
    };
    try expectSchema(Doc,
        \\"type":"object","properties":{"levelName":{"enum":["low","high"],"default":"low"},"tags":{"type":"array","items":{"type":"integer"},"minItems":1,"maxItems":3,"uniqueItems":true,"default":[]},"tier":{"type":"integer","minimum":0,"maximum":255,"enum":[1,2,3],"default":1}},"required":[],"additionalProperties":false}
    );
}

test "json schema: string formats and anchored patterns" {
    const Contact = struct {
        email: []const u8,
        code: []const u8,

        pub const serval = .{
            .fields = .{
                .email = .{ .email = true },
                .code = .{ .pattern = "a+", .pattern_full = true },
            },
        };
    };
    try expectSchema(Contact,
        \\"type":"object","properties":{"email":{"type":"string","format":"email"},"code":{"type":"string","pattern":"^(?:a+)$"}},"required":["email","code"],"additionalProperties":false}
    );
}

test "json schema: internal union as oneOf with const tags" {
    const Shape = union(enum) {
        circle: struct { r: f64 },
        point: void,

        pub const serval = .{ .union_tagging = .internal, .union_tag_field = "kind" };
    };
    try expectSchema(Shape,
        \\"oneOf":[{"type":"object","properties":{"kind":{"const":"circle"},"r":{"type":"number"}},"required":["kind","r"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"point"}},"required":["kind"],"additionalProperties":false}]}
    );
}

test "json schema: external union mixes const strings and payload objects" {
    const Ev = union(enum) {
        ping: void,
        count: u32,
    };
    try expectSchema(Ev,
        \\"oneOf":[{"const":"ping"},{"type":"object","properties":{"count":{"type":"integer","minimum":0,"maximum":4294967295}},"required":["count"],"additionalProperties":false}]}
    );
}

test "json schema: bytes policy maps to byte arrays, nested structs inline" {
    const Blob = struct {
        data: []const u8,
        inner: struct { x: f32 = 0 } = .{},

        pub const serval = .{ .bytes_policy = .bytes };
    };
    try expectSchema(Blob,
        \\"type":"object","properties":{"data":{"type":"array","items":{"type":"integer","minimum":0,"maximum":255}},"inner":{"type":"object","properties":{"x":{"type":"number","default":0}},"required":[],"additionalProperties":false,"default":{"x":0}}},"required":["data"],"additionalProperties":false}
    );
}
