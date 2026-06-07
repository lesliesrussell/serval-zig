// serval-13k
//! Real-world schema exercises — non-trivial shapes that surface
//! ergonomics issues synthetic tests miss. Friction found here is filed
//! as beads, not worked around silently.

const std = @import("std");
const serval = @import("serval");
// ERGONOMICS FINDING (filed): inside a type declaring `pub const serval`,
// the metadata decl shadows the conventional import alias — hooks must
// reference library types through a file-scope alias like this one.
const ValidateContext = serval.core.ValidateContext;
const Path = serval.core.Path;

// --- 1. OpenAPI document fragment ------------------------------------------
// Exercises: wire-name renames that aren't Zig identifiers ("200",
// "application/json", "$ref"), untagged unions matched by shape
// ($ref-or-inline-schema, exactly how OpenAPI does it), deep optionals.
//
// ERGONOMICS FINDING (filed): OpenAPI's `paths` is a string-keyed map of
// arbitrary keys — serval has no map type, so a known path is modeled via
// rename and arbitrary paths need the dynamic Value API. A typed
// string-map (std.StringArrayHashMap-backed or assoc-slice) would close
// this.

const SchemaOrRef = union(enum) {
    // ref first: more specific shape wins under first_match
    ref: struct {
        ref: []const u8,

        pub const serval = .{ .fields = .{ .ref = .{ .rename = "$ref" } } };
    },
    inline_schema: struct {
        type: []const u8,
        format: ?[]const u8 = null,
    },

    pub const serval = .{ .union_tagging = .untagged };
};

const Parameter = struct {
    name: []const u8,
    in: enum { query, header, path },
    required: bool = false,
    schema: ?SchemaOrRef = null,
};

const MediaType = struct { schema: SchemaOrRef };

const Response = struct {
    description: []const u8,
    content: ?struct {
        json: ?MediaType = null,

        pub const serval = .{ .fields = .{ .json = .{ .rename = "application/json" } } };
    } = null,
};

const Operation = struct {
    operation_id: []const u8,
    summary: ?[]const u8 = null,
    parameters: []const Parameter = &.{},
    responses: struct {
        ok: Response,
        not_found: ?Response = null,

        pub const serval = .{ .fields = .{
            .ok = .{ .rename = "200" },
            .not_found = .{ .rename = "404" },
        } };
    },

    pub const serval = .{ .rename_all = .camel_case };
};

const openapi_fragment =
    \\{
    \\  "operationId": "getUser",
    \\  "summary": "Fetch a user by id",
    \\  "parameters": [
    \\    {"name": "id", "in": "path", "required": true,
    \\     "schema": {"type": "integer", "format": "int64"}},
    \\    {"name": "verbose", "in": "query",
    \\     "schema": {"$ref": "#/components/schemas/Flag"}}
    \\  ],
    \\  "responses": {
    \\    "200": {"description": "the user",
    \\            "content": {"application/json":
    \\              {"schema": {"$ref": "#/components/schemas/User"}}}},
    \\    "404": {"description": "no such user"}
    \\  }
    \\}
;

test "openapi: operation fragment decodes with renames and shape-matched unions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const op = try serval.json.decode(Operation, arena.allocator(), openapi_fragment, .{});
    try std.testing.expectEqualStrings("getUser", op.operation_id);
    try std.testing.expectEqual(@as(usize, 2), op.parameters.len);

    // inline schema vs $ref resolved by shape
    try std.testing.expectEqualStrings("integer", op.parameters[0].schema.?.inline_schema.type);
    try std.testing.expectEqualStrings("#/components/schemas/Flag", op.parameters[1].schema.?.ref.ref);

    // "200"/"404"/"application/json" renames
    try std.testing.expectEqualStrings("the user", op.responses.ok.description);
    try std.testing.expectEqualStrings(
        "#/components/schemas/User",
        op.responses.ok.content.?.json.?.schema.ref.ref,
    );
    try std.testing.expectEqualStrings("no such user", op.responses.not_found.?.description);
}

test "openapi: arbitrary path keys go through the dynamic Value API" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // the documented workaround for string-keyed maps
    const paths_doc =
        \\{"/users/{id}": {"get": null}, "/health": {"get": null}}
    ;
    const v = try serval.json.decodeValue(arena.allocator(), paths_doc, .{});
    try std.testing.expectEqual(@as(usize, 2), v.object.len);
    try std.testing.expectEqualStrings("/users/{id}", v.object[0].name);
}

// --- 2. Layered application config ------------------------------------------
// Exercises: defaults everywhere, internal-tagged union sections,
// transforms + membership on env knobs, presence-driven cross-field
// rules, and the same shape from both JSON and ZON.

const Server = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 8080,

    pub const serval = .{ .fields = .{ .port = .{ .min = 1 } } };
};

const Database = union(enum) {
    sqlite: struct { path: []const u8 },
    postgres: struct {
        host: []const u8,
        port: u16 = 5432,
        database: []const u8,
    },

    pub const serval = .{ .union_tagging = .internal, .union_tag_field = "driver" };
};

const Config = struct {
    env: []const u8 = "dev",
    log_level: enum { debug, info, warn, err } = .info,
    server: Server = .{},
    database: Database,
    admin_email: ?[]const u8 = null,

    pub const serval = .{
        .fields = .{
            .env = .{ .trim = true, .lowercase = true, .one_of_str = &.{ "dev", "staging", "prod" } },
            .admin_email = .{ .trim = true, .lowercase = true, .email = true },
        },
    };

    pub fn servalValidate(ctx: *ValidateContext, self: *const @This()) void {
        if (std.mem.eql(u8, self.env, "prod") and !ctx.has("admin_email")) {
            ctx.issue(.{
                .path = Path.field("admin_email"),
                .code = .required_when,
                .message = "required when env is prod",
            });
        }
    }
};

test "config: json with transforms, internal union, defaults, presence rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg = try serval.json.decode(Config, a,
        \\{"env":" PROD ", "admin_email":"  Ops@Example.COM ",
        \\ "database": {"driver":"postgres","host":"db.internal","database":"app"}}
    , .{});
    try std.testing.expectEqualStrings("prod", cfg.env); // trimmed + lowered
    try std.testing.expectEqualStrings("ops@example.com", cfg.admin_email.?);
    try std.testing.expectEqual(@as(u16, 5432), cfg.database.postgres.port); // payload default
    try std.testing.expectEqual(@as(u16, 8080), cfg.server.port); // whole-section default

    // prod without admin_email: the presence rule fires
    const dr = try serval.json.decodeResult(Config, a,
        \\{"env":"prod","database":{"driver":"sqlite","path":"/tmp/app.db"}}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.required_when, dr.invalid.issues[0].code);

    // membership violation reads well
    const bad_env = try serval.json.decodeResult(Config, a,
        \\{"env":"production","database":{"driver":"sqlite","path":"x"}}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.one_of, bad_env.invalid.issues[0].code);
}

// serval-gy5
test "metadata: serval_schema decl avoids shadowing the import alias" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const T = struct {
        name: []const u8,

        // alternate decl name: hooks can reference `serval.` directly
        pub const serval_schema = .{ .fields = .{ .name = .{ .min_len = 2 } } };

        pub fn servalValidate(ctx: *serval.core.ValidateContext, self: *const @This()) void {
            if (std.mem.startsWith(u8, self.name, "x")) {
                ctx.issue(.{
                    .path = serval.core.Path.field("name"),
                    .code = .custom,
                    .message = "names may not start with x",
                });
            }
        }
    };

    // metadata honored through the alternate name
    const dr = try serval.json.decodeResult(T, arena.allocator(),
        \\{"name":"a"}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.min_len, dr.invalid.issues[0].code);

    // hook references serval.* without any file-scope alias
    const hooked = try serval.json.decodeResult(T, arena.allocator(),
        \\{"name":"xeno"}
    , .{});
    try std.testing.expectEqual(serval.core.IssueCode.custom, hooked.invalid.issues[0].code);
}

test "config: same shape from ZON within its declared capabilities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // ZON: native union syntax (serval tagging metadata not honored —
    // declared gap), no transforms/presence — so this document is
    // pre-normalized. ERGONOMICS FINDING (filed): transforms silently
    // don't run on the zon path and aren't in the capability flags.
    const cfg = try serval.zon.decode(Config, arena.allocator(),
        \\.{
        \\  .env = "staging",
        \\  .log_level = .warn,
        \\  .database = .{ .postgres = .{ .host = "db", .database = "app" } },
        \\}
    , .{ .memory = .arena });
    try std.testing.expectEqualStrings("staging", cfg.env);
    try std.testing.expectEqual(.warn, cfg.log_level);
    try std.testing.expectEqual(@as(u16, 5432), cfg.database.postgres.port);
    try std.testing.expectEqualStrings("0.0.0.0", cfg.server.host);
}
