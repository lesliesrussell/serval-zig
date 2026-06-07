// serval-wf8
//! Schema export parity: every constraint keyword the exporter emits is
//! backed by matching serval validation behavior — conforming instances
//! pass, violating instances fail with the corresponding classification.
//! This is keyword-level SELF-consistency (no Zig JSON Schema validator
//! exists; external-validator parity is out of scope). The case table
//! doubles as the keyword ↔ IssueCode correspondence documentation.

const std = @import("std");
const serval = @import("serval");

const Outcome = union(enum) {
    issue: serval.core.IssueCode,
    err: anyerror,
};

fn expectParity(
    comptime F: type,
    comptime keyword: []const u8,
    valid_doc: []const u8,
    invalid_doc: []const u8,
    comptime outcome: Outcome,
) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // the exporter actually claims this keyword for F
    const schema = try serval.schema_export.jsonSchema(F, a);
    if (std.mem.indexOf(u8, schema, keyword) == null) {
        std.debug.print("keyword '{s}' missing from emitted schema:\n{s}\n", .{ keyword, schema });
        return error.TestExpectedKeyword;
    }

    // conforming instance passes serval validation
    _ = try serval.json.decode(F, a, valid_doc, .{});

    // violating instance fails with the corresponding classification
    switch (outcome) {
        .issue => |code| {
            const dr = try serval.json.decodeResult(F, a, invalid_doc, .{});
            try std.testing.expect(dr == .invalid);
            try std.testing.expectEqual(code, dr.invalid.issues[0].code);
        },
        .err => |e| {
            try std.testing.expectError(e, serval.json.decode(F, a, invalid_doc, .{}));
        },
    }
}

// --- keyword ↔ behavior correspondence table --------------------------------

test "parity: minimum / maximum (meta bounds)" {
    const F = struct {
        n: i32,

        pub const serval = .{ .fields = .{ .n = .{ .min = 10, .max = 20 } } };
    };
    try expectParity(F, "\"minimum\":10",
        \\{"n":15}
    ,
        \\{"n":5}
    , .{ .issue = .min });
    try expectParity(F, "\"maximum\":20",
        \\{"n":15}
    ,
        \\{"n":25}
    , .{ .issue = .max });
}

test "parity: integer type bounds (maximum from u8)" {
    const F = struct { n: u8 };
    try expectParity(F, "\"maximum\":255",
        \\{"n":255}
    ,
        \\{"n":300}
    , .{ .err = error.Overflow });
}

test "parity: exclusiveMinimum / exclusiveMaximum" {
    const F = struct {
        n: i32,

        pub const serval = .{ .fields = .{ .n = .{ .gt = 0, .lt = 100 } } };
    };
    try expectParity(F, "\"exclusiveMinimum\":0",
        \\{"n":1}
    ,
        \\{"n":0}
    , .{ .issue = .gt });
    try expectParity(F, "\"exclusiveMaximum\":100",
        \\{"n":99}
    ,
        \\{"n":100}
    , .{ .issue = .lt });
}

test "parity: minLength / maxLength / nonempty" {
    const F = struct {
        s: []const u8,

        pub const serval = .{ .fields = .{ .s = .{ .min_len = 2, .max_len = 4 } } };
    };
    try expectParity(F, "\"minLength\":2",
        \\{"s":"ab"}
    ,
        \\{"s":"a"}
    , .{ .issue = .min_len });
    try expectParity(F, "\"maxLength\":4",
        \\{"s":"abcd"}
    ,
        \\{"s":"abcde"}
    , .{ .issue = .max_len });

    const NE = struct {
        s: []const u8,

        pub const serval = .{ .fields = .{ .s = .{ .nonempty = true } } };
    };
    try expectParity(NE, "\"minLength\":1",
        \\{"s":"x"}
    ,
        \\{"s":""}
    , .{ .issue = .nonempty });
}

test "parity: pattern (anchored under pattern_full)" {
    const F = struct {
        s: []const u8,

        pub const serval = .{ .fields = .{ .s = .{ .pattern = "a+", .pattern_full = true } } };
    };
    try expectParity(F, "\"pattern\":\"^(?:a+)$\"",
        \\{"s":"aaa"}
    ,
        \\{"s":"baa"}
    , .{ .issue = .pattern });
}

test "parity: format email" {
    const F = struct {
        s: []const u8,

        pub const serval = .{ .fields = .{ .s = .{ .email = true } } };
    };
    try expectParity(F, "\"format\":\"email\"",
        \\{"s":"a@b.io"}
    ,
        \\{"s":"nope"}
    , .{ .issue = .email });
}

test "parity: enum (membership, string membership, enum tags)" {
    const M = struct {
        n: u8,

        pub const serval = .{ .fields = .{ .n = .{ .one_of = &.{ 1, 2, 3 } } } };
    };
    try expectParity(M, "\"enum\":[1,2,3]",
        \\{"n":2}
    ,
        \\{"n":9}
    , .{ .issue = .one_of });

    const S = struct {
        s: []const u8,

        pub const serval = .{ .fields = .{ .s = .{ .one_of_str = &.{ "us", "eu" } } } };
    };
    try expectParity(S, "\"enum\":[\"us\",\"eu\"]",
        \\{"s":"eu"}
    ,
        \\{"s":"jp"}
    , .{ .issue = .one_of });

    const E = struct { level: enum { low, high } };
    try expectParity(E, "\"enum\":[\"low\",\"high\"]",
        \\{"level":"low"}
    ,
        \\{"level":"medium"}
    , .{ .err = error.InvalidEnumTag });
}

test "parity: minItems / maxItems / uniqueItems" {
    const F = struct {
        xs: []const i64,

        pub const serval = .{ .fields = .{ .xs = .{ .min_items = 1, .max_items = 2, .unique = true } } };
    };
    try expectParity(F, "\"minItems\":1",
        \\{"xs":[1]}
    ,
        \\{"xs":[]}
    , .{ .issue = .min_items });
    try expectParity(F, "\"maxItems\":2",
        \\{"xs":[1,2]}
    ,
        \\{"xs":[1,2,3]}
    , .{ .issue = .max_items });
    try expectParity(F, "\"uniqueItems\":true",
        \\{"xs":[1,2]}
    ,
        \\{"xs":[1,1]}
    , .{ .issue = .unique });
}

test "parity: required / additionalProperties:false" {
    const F = struct { must: []const u8 };
    try expectParity(F, "\"required\":[\"must\"]",
        \\{"must":"x"}
    , "{}", .{ .issue = .required });
    try expectParity(F, "\"additionalProperties\":false",
        \\{"must":"x"}
    ,
        \\{"must":"x","extra":1}
    , .{ .err = error.UnknownField });
}

test "parity: oneOf with const tags (unions)" {
    const F = union(enum) {
        ping: void,
        count: u32,
    };
    try expectParity(F, "\"oneOf\":[{\"const\":\"ping\"}",
        \\{"count":3}
    ,
        \\{"blip":3}
    , .{ .err = error.InvalidEnumTag });
}
