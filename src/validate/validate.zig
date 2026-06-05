// serval-15q
//! Validation engine entry points.

const std = @import("std");
const core = @import("serval-core");
const coercion = @import("coercion.zig");

pub const CheckOptions = struct {
    coercion: coercion.CoercionMode = .none,
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
    _ = options;
    var ctx = core.ValidateContext.init(allocator);
    errdefer ctx.deinit();

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

// serval-bfp
fn checkValue(comptime f: core.Field, v: anytype, ctx: *core.ValidateContext) void {
    const V = @TypeOf(v);
    switch (@typeInfo(V)) {
        .optional => if (v) |payload| checkValue(f, payload, ctx),
        .int => checkScalar(f, v, ctx),
        .pointer => |p| {
            if (p.size != .slice) return;
            if (p.child == u8)
                checkString(f, v, ctx)
            else
                checkCollection(f, v, ctx);
        },
        // TODO(serval): float scalar rules once FieldMeta grows f64 bounds.
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
    // TODO(serval): .pattern needs a regex engine decision (none in std).
}

// serval-bfp
fn checkCollection(comptime f: core.Field, v: anytype, ctx: *core.ValidateContext) void {
    const m = f.meta;
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
