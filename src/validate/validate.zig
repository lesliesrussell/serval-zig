// serval-15q
//! Validation engine entry points.

const std = @import("std");
const core = @import("serval-core");
const coercion = @import("coercion.zig");
// serval-bcz
const mvzr = @import("mvzr");

pub const CheckOptions = struct {
    // serval-4tr: honored by valueAgainstSchema (dynamic Values can be
    // coercible); ignored by typed check() — typed values already have
    // their final types, coercion is a decode-time concern there.
    coercion: coercion.CoercionMode = .none,
    // serval-r4h
    /// Zig field names present in decoded input; feeds ValidateContext.has().
    /// Set by the decode pipeline — leave empty for standalone checks.
    present_fields: []const []const u8 = &.{},
};

// serval-bfp
/// Validate a typed value against its schema.
/// Caller owns `report.issues` (free with the same allocator).
///
/// Runs constraint validation (phase 3) driven by Schema(T) field metadata,
/// then the struct-level `pub fn servalValidate(ctx, self)` hook if declared.
/// Phases 1–2 (shape, coercion/defaulting) operate on wire input and land
/// with the decode pipeline.
pub fn check(
    comptime T: type,
    value: *const T,
    allocator: std.mem.Allocator,
    options: CheckOptions,
) !core.ValidationReport {
    var ctx = core.ValidateContext.init(allocator);
    errdefer ctx.deinit();
    // serval-r4h
    ctx.present_fields = options.present_fields;

    const S = core.schemaOf(T);
    inline for (S.fields) |f| {
        checkValue(f, @field(value.*, f.name), &ctx);
    }
    if (@hasDecl(T, "servalValidate")) {
        T.servalValidate(&ctx, value);
    }

    const issues = try ctx.issues.toOwnedSlice(ctx.allocator);
    return .{ .issues = issues };
}

// serval-l3p
/// Validate an untyped core.Value tree against Schema(T): shape
/// (invalid_type / required / unknown_field) plus the same constraint rules
/// as check(). Paths are innermost-field-level. Union payloads are
/// shallow-checked (shape only at the union node).
pub fn valueAgainstSchema(
    comptime T: type,
    value: core.Value,
    allocator: std.mem.Allocator,
    options: CheckOptions,
) error{OutOfMemory}!core.ValidationReport {
    var ctx = core.ValidateContext.init(allocator);
    errdefer ctx.deinit();
    // serval-4tr: coercion-aware shape checks — a coercible value passes
    // and constraints run against the coerced result.
    if (@typeInfo(T) == .@"struct") {
        checkStructNode(T, value, &ctx, options.coercion);
    } else {
        checkFieldNode(T, .{ .name = "value", .wire_name = "value" }, value, &ctx, .{}, options.coercion);
    }
    const issues = try ctx.issues.toOwnedSlice(ctx.allocator);
    return .{ .issues = issues };
}

// serval-l3p
fn checkStructNode(comptime T: type, v: core.Value, ctx: *core.ValidateContext, mode: coercion.CoercionMode) void {
    const obj = switch (v) {
        .object => |o| o,
        else => {
            ctx.issue(.{ .path = .root, .code = .invalid_type, .message = "expected object" });
            return;
        },
    };
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;

    outer: for (obj) |fv| {
        inline for (S.fields) |sf| {
            if (std.mem.eql(u8, fv.name, sf.wire_name)) continue :outer;
        }
        ctx.issue(.{ .path = .root, .code = .unknown_field, .message = "unknown field in value" });
    }

    inline for (S.fields, struct_fields) |sf, zf| {
        const found: ?core.Value = blk: {
            for (obj) |fv| {
                if (std.mem.eql(u8, fv.name, sf.wire_name)) break :blk fv.value;
            }
            break :blk null;
        };
        if (found) |fval| {
            checkFieldNode(zf.type, sf, fval, ctx, S.options, mode);
        } else if (zf.defaultValue() == null and @typeInfo(zf.type) != .optional) {
            ctx.issue(.{ .path = .field(sf.name), .code = .required, .message = "missing required field" });
        }
    }
}

// serval-l3p
fn checkFieldNode(
    comptime FT: type,
    comptime sf: core.Field,
    v: core.Value,
    ctx: *core.ValidateContext,
    comptime parent: core.TypeOptions,
    mode: coercion.CoercionMode,
) void {
    switch (@typeInfo(FT)) {
        .optional => |o| {
            if (v == .null) return;
            checkFieldNode(o.child, sf, v, ctx, parent, mode);
        },
        // serval-4tr: coercible values pass shape and run constraints on
        // the coerced result. Aggressive scalar→string is shape-accepted
        // without string constraints (no allocator in this walker).
        .bool => switch (v) {
            .bool => {},
            .string => |s| {
                if (mode == .none or coercion.boolFromString(s) == null)
                    invalidType(sf, ctx, "expected bool");
            },
            .int => |n| {
                if (mode != .aggressive or coercion.boolFromInt(n) == null)
                    invalidType(sf, ctx, "expected bool");
            },
            else => invalidType(sf, ctx, "expected bool"),
        },
        .int => switch (v) {
            .int => |n| checkScalar(sf, n, ctx),
            .string => |s| {
                if (mode != .none) {
                    if (coercion.intFromString(FT, s)) |n| {
                        checkScalar(sf, n, ctx);
                        return;
                    }
                }
                invalidType(sf, ctx, "expected integer");
            },
            .float => |fl| {
                if (mode == .aggressive) {
                    if (coercion.intFromFloat(FT, fl)) |n| {
                        checkScalar(sf, n, ctx);
                        return;
                    }
                }
                invalidType(sf, ctx, "expected integer");
            },
            else => invalidType(sf, ctx, "expected integer"),
        },
        .float => switch (v) {
            .float => |fl| checkScalarFloat(sf, fl, ctx),
            .int => |n| checkScalarFloat(sf, @as(f64, @floatFromInt(n)), ctx),
            .string => |s| {
                if (mode != .none) {
                    if (coercion.floatFromString(f64, s)) |fl| {
                        checkScalarFloat(sf, fl, ctx);
                        return;
                    }
                }
                invalidType(sf, ctx, "expected number");
            },
            else => invalidType(sf, ctx, "expected number"),
        },
        .@"enum" => switch (parent.enum_tagging) {
            .name => switch (v) {
                .string => |s| if (std.meta.stringToEnum(FT, s) == null)
                    invalidType(sf, ctx, "not a valid enum tag"),
                else => invalidType(sf, ctx, "expected enum tag string"),
            },
            .value => switch (v) {
                .int => |n| if (std.enums.fromInt(FT, n) == null)
                    invalidType(sf, ctx, "not a valid enum value"),
                else => invalidType(sf, ctx, "expected enum tag integer"),
            },
        },
        .pointer => |p| {
            if (p.size != .slice) return;
            if (p.child == u8 and parent.bytes_policy == .string) {
                switch (v) {
                    .string, .bytes => |s| checkString(sf, s, ctx),
                    else => invalidType(sf, ctx, "expected string"),
                }
                return;
            }
            if (p.child == u8) {
                switch (v) {
                    .string, .bytes => {},
                    else => invalidType(sf, ctx, "expected bytes"),
                }
                return;
            }
            switch (v) {
                .array => |items| {
                    const m = sf.meta;
                    // serval-elw
                    if (m.nonempty and items.len == 0) ctx.issue(.{
                        .path = .field(sf.name),
                        .code = .nonempty,
                        .message = "collection must not be empty",
                    });
                    if (m.min_items) |lim| if (items.len < lim) ctx.issue(.{
                        .path = .field(sf.name),
                        .code = .min_items,
                        .message = "fewer items than min_items",
                    });
                    if (m.max_items) |lim| if (items.len > lim) ctx.issue(.{
                        .path = .field(sf.name),
                        .code = .max_items,
                        .message = "more items than max_items",
                    });
                    // Elements: shape only — field constraints don't apply
                    // to individual elements. (.unique is skipped on the
                    // dynamic path: Value equality semantics are undefined.)
                    const element_field = comptime core.Field{
                        .name = sf.name,
                        .wire_name = sf.wire_name,
                    };
                    for (items) |item| checkFieldNode(p.child, element_field, item, ctx, parent, mode);
                },
                else => invalidType(sf, ctx, "expected array"),
            }
        },
        .@"struct" => checkStructNode(FT, v, ctx, mode),
        // TODO(serval): deep union shape checks per tagging mode.
        .@"union" => {},
        else => {},
    }
}

// serval-l3p
fn invalidType(comptime sf: core.Field, ctx: *core.ValidateContext, message: []const u8) void {
    ctx.issue(.{ .path = .field(sf.name), .code = .invalid_type, .message = message });
}

// serval-bfp
fn checkValue(comptime f: core.Field, v: anytype, ctx: *core.ValidateContext) void {
    const V = @TypeOf(v);
    switch (@typeInfo(V)) {
        .optional => if (v) |payload| checkValue(f, payload, ctx),
        .int => checkScalar(f, v, ctx),
        // serval-yus
        .float => checkScalarFloat(f, v, ctx),
        .pointer => |p| {
            if (p.size != .slice) return;
            if (p.child == u8)
                checkString(f, v, ctx)
            else
                checkCollection(f, v, ctx);
        },
        else => {},
    }
}

// serval-bfp
fn checkScalar(comptime f: core.Field, v: anytype, ctx: *core.ValidateContext) void {
    const m = f.meta;
    const x: i128 = v;
    if (m.min) |lim| if (x < lim) issueScalar(f, ctx, .min, "value below minimum", lim, v);
    if (m.max) |lim| if (x > lim) issueScalar(f, ctx, .max, "value above maximum", lim, v);
    if (m.gt) |lim| if (x <= lim) issueScalar(f, ctx, .gt, "value must be greater", lim, v);
    if (m.lt) |lim| if (x >= lim) issueScalar(f, ctx, .lt, "value must be smaller", lim, v);
    // serval-elw
    if (m.one_of) |allowed| {
        for (allowed) |a| {
            if (x == a) return;
        }
        ctx.issue(.{
            .path = .field(f.name),
            .code = .one_of,
            .message = "value not in allowed set",
            .actual = if (std.math.cast(i64, v)) |a| .{ .int = a } else null,
        });
    }
}

// serval-yus
/// Floats reuse the i64 scalar bounds — integral bounds only (a .min of
/// 0.5 is not expressible; use a custom validator for fractional limits).
fn checkScalarFloat(comptime f: core.Field, v: anytype, ctx: *core.ValidateContext) void {
    const m = f.meta;
    const x: f64 = v;
    if (m.min) |lim| if (x < @as(f64, @floatFromInt(lim))) issueFloat(f, ctx, .min, "value below minimum", lim, x);
    if (m.max) |lim| if (x > @as(f64, @floatFromInt(lim))) issueFloat(f, ctx, .max, "value above maximum", lim, x);
    if (m.gt) |lim| if (x <= @as(f64, @floatFromInt(lim))) issueFloat(f, ctx, .gt, "value must be greater", lim, x);
    if (m.lt) |lim| if (x >= @as(f64, @floatFromInt(lim))) issueFloat(f, ctx, .lt, "value must be smaller", lim, x);
}

// serval-yus
fn issueFloat(
    comptime f: core.Field,
    ctx: *core.ValidateContext,
    code: core.IssueCode,
    message: []const u8,
    expected: i64,
    actual: f64,
) void {
    ctx.issue(.{
        .path = .field(f.name),
        .code = code,
        .message = message,
        .expected = .{ .int = expected },
        .actual = .{ .float = actual },
    });
}

// serval-bfp
fn issueScalar(
    comptime f: core.Field,
    ctx: *core.ValidateContext,
    code: core.IssueCode,
    message: []const u8,
    expected: i64,
    actual: anytype,
) void {
    ctx.issue(.{
        .path = .field(f.name),
        .code = code,
        .message = message,
        .expected = .{ .int = expected },
        .actual = if (std.math.cast(i64, actual)) |a| .{ .int = a } else null,
    });
}

// serval-bfp
fn checkString(comptime f: core.Field, v: []const u8, ctx: *core.ValidateContext) void {
    const m = f.meta;
    // serval-elw
    if (m.nonempty and v.len == 0) ctx.issue(.{
        .path = .field(f.name),
        .code = .nonempty,
        .message = "string must not be empty",
    });
    if (m.one_of_str) |allowed| {
        const member = for (allowed) |a| {
            if (std.mem.eql(u8, v, a)) break true;
        } else false;
        if (!member) ctx.issue(.{
            .path = .field(f.name),
            .code = .one_of,
            .message = "string not in allowed set",
            .actual = .{ .string = v },
        });
    }
    if (m.min_len) |lim| if (v.len < lim) ctx.issue(.{
        .path = .field(f.name),
        .code = .min_len,
        .message = "string shorter than min_len",
        .expected = .{ .int = @intCast(lim) },
        .actual = .{ .int = @intCast(v.len) },
    });
    if (m.max_len) |lim| if (v.len > lim) ctx.issue(.{
        .path = .field(f.name),
        .code = .max_len,
        .message = "string longer than max_len",
        .expected = .{ .int = @intCast(lim) },
        .actual = .{ .int = @intCast(v.len) },
    });
    if (m.email and !isEmail(v)) ctx.issue(.{
        .path = .field(f.name),
        .code = .email,
        .message = "not a valid email address",
        .actual = .{ .string = v },
    });
    if (m.url and !isUrl(v)) ctx.issue(.{
        .path = .field(f.name),
        .code = .url,
        .message = "not a valid URL",
        .actual = .{ .string = v },
    });
    // serval-yus: patterns compile once at comptime; an uncompilable
    // pattern is a compile error, not a runtime issue.
    if (m.pattern) |pat| {
        const rx = comptime mvzr.compile(pat) orelse
            @compileError("serval: invalid regex in .pattern rule: " ++ pat);
        if (!rx.isMatch(v)) ctx.issue(.{
            .path = .field(f.name),
            .code = .pattern,
            .message = "string does not match pattern",
            .expected = .{ .string = pat },
            .actual = .{ .string = v },
        });
    }
}

// serval-bfp
fn checkCollection(comptime f: core.Field, v: anytype, ctx: *core.ValidateContext) void {
    const m = f.meta;
    // serval-elw
    if (m.nonempty and v.len == 0) ctx.issue(.{
        .path = .field(f.name),
        .code = .nonempty,
        .message = "collection must not be empty",
    });
    if (m.min_items) |lim| if (v.len < lim) ctx.issue(.{
        .path = .field(f.name),
        .code = .min_items,
        .message = "fewer items than min_items",
        .expected = .{ .int = @intCast(lim) },
        .actual = .{ .int = @intCast(v.len) },
    });
    if (m.max_items) |lim| if (v.len > lim) ctx.issue(.{
        .path = .field(f.name),
        .code = .max_items,
        .message = "more items than max_items",
        .expected = .{ .int = @intCast(lim) },
        .actual = .{ .int = @intCast(v.len) },
    });
    if (m.unique) {
        outer: for (v, 0..) |a, i| {
            for (v[i + 1 ..]) |b| {
                if (std.meta.eql(a, b)) {
                    ctx.issue(.{
                        .path = .field(f.name),
                        .code = .unique,
                        .message = "duplicate items in unique collection",
                    });
                    break :outer;
                }
            }
        }
    }
}

// serval-bfp
/// Minimal v1 email shape check: nonempty local @ domain containing a dot.
fn isEmail(s: []const u8) bool {
    const at = std.mem.indexOfScalar(u8, s, '@') orelse return false;
    if (at == 0 or at + 1 >= s.len) return false;
    const domain = s[at + 1 ..];
    if (std.mem.indexOfScalar(u8, domain, '@') != null) return false;
    const dot = std.mem.indexOfScalar(u8, domain, '.') orelse return false;
    return dot != 0 and dot != domain.len - 1;
}

// serval-bfp
/// Minimal v1 URL shape check: http(s) scheme with nonempty host.
fn isUrl(s: []const u8) bool {
    inline for (.{ "http://", "https://" }) |prefix| {
        if (std.mem.startsWith(u8, s, prefix)) return s.len > prefix.len;
    }
    return false;
}
