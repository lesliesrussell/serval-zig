// serval-15q
//! Validation engine entry points.

const std = @import("std");
const core = @import("serval-core");
const coercion = @import("coercion.zig");

pub const CheckOptions = struct {
    coercion: coercion.CoercionMode = .none,
};

/// Validate a typed value against its schema.
/// Caller owns `report.issues` (free with the same allocator).
///
/// Scaffold: runs no rules yet. The three phases land in order:
///   1. shape validation (required/unknown fields, type mismatches, tags)
///   2. coercion/defaulting
///   3. constraint validation (ranges, lengths, patterns, cross-field)
pub fn check(
    comptime T: type,
    value: *const T,
    allocator: std.mem.Allocator,
    options: CheckOptions,
) !core.ValidationReport {
    _ = value;
    _ = options;
    const S = core.schemaOf(T);
    _ = S;
    var ctx = core.ValidateContext.init(allocator);
    defer ctx.deinit();
    const issues = try ctx.issues.toOwnedSlice(ctx.allocator);
    return .{ .issues = issues };
}
