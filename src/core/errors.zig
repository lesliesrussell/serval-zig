// serval-15q
//! Path-aware validation errors and decode error sets.
//! Validation is never just `error.Invalid` — every issue carries a path,
//! a code, and a message.

const value_mod = @import("value.zig");

pub const PathSegment = union(enum) {
    field: []const u8,
    index: usize,
    key: []const u8,
    variant: []const u8,
};

pub const Path = struct {
    segments: []const PathSegment = &.{},

    /// Convenience single-field path (comptime names only for now;
    /// runtime path building lands with the validation engine).
    pub fn field(comptime name: []const u8) Path {
        return .{ .segments = &.{.{ .field = name }} };
    }

    pub const root: Path = .{};
};

pub const IssueCode = enum {
    invalid_type,
    required,
    required_when,
    unknown_field,
    min,
    max,
    gt,
    lt,
    one_of,
    min_len,
    max_len,
    pattern,
    email,
    url,
    min_items,
    max_items,
    unique,
    nonempty,
    custom,
};

pub const ValidationIssue = struct {
    path: Path,
    code: IssueCode,
    message: []const u8,
    expected: ?value_mod.Value = null,
    actual: ?value_mod.Value = null,
};

pub const ValidationReport = struct {
    issues: []const ValidationIssue = &.{},

    pub fn ok(self: ValidationReport) bool {
        return self.issues.len == 0;
    }
};

/// Syntax-level failures — a different class of problem from semantic
/// validation failures (which produce a ValidationReport instead).
pub const DecodeError = error{
    UnexpectedToken,
    UnexpectedEndOfInput,
    InvalidSyntax,
    Overflow,
    OutOfMemory,
};
