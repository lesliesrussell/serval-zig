// serval-15q
//! Path-aware validation errors and decode error sets.
//! Validation is never just `error.Invalid` — every issue carries a path,
//! a code, and a message.

const std = @import("std");
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

    // serval-sru
    /// Renders `.field[3].nested` style; "(root)" when empty. `{f}`-able.
    pub fn format(self: Path, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.segments.len == 0) return writer.writeAll("(root)");
        for (self.segments) |seg| switch (seg) {
            .field, .variant => |n| {
                try writer.writeByte('.');
                try writer.writeAll(n);
            },
            .index => |i| try writer.print("[{d}]", .{i}),
            .key => |k| try writer.print("[\"{s}\"]", .{k}),
        };
    }
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

    // serval-sru
    /// Issue paths are runtime-built and allocator-owned — free reports
    /// with this (or decode/validate with an arena).
    pub fn deinit(self: ValidationReport, allocator: std.mem.Allocator) void {
        for (self.issues) |i| allocator.free(i.path.segments);
        allocator.free(self.issues);
    }

    // serval-3g8
    /// Human-readable rendering: one line per issue, path-first (full
    /// nested/array paths), expected/actual appended when present.
    /// Issues arrive in field-walk order, so related paths cluster.
    pub fn render(self: ValidationReport, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("validation failed ({d} issue{s}):\n", .{
            self.issues.len,
            if (self.issues.len == 1) "" else "s",
        });
        for (self.issues) |i| {
            try writer.print("  {f}: {s}", .{ i.path, i.message });
            if (i.expected != null or i.actual != null) {
                try writer.writeAll(" (");
                if (i.expected) |e| {
                    try writer.writeAll("expected ");
                    try renderValueBrief(e, writer);
                }
                if (i.actual) |a| {
                    if (i.expected != null) try writer.writeAll(", ");
                    try writer.writeAll("actual ");
                    try renderValueBrief(a, writer);
                }
                try writer.writeAll(")");
            }
            try writer.writeAll("\n");
        }
    }
};

// serval-3g8
fn renderValueBrief(v: value_mod.Value, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (v) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .int => |n| try writer.print("{d}", .{n}),
        .float => |f| try writer.print("{d}", .{f}),
        .string => |s| try writer.print("\"{s}\"", .{s}),
        .bytes => |b| try writer.print("{d} bytes", .{b.len}),
        .array => |a| try writer.print("[{d} items]", .{a.len}),
        .object => |o| try writer.print("{{{d} fields}}", .{o.len}),
    }
}

/// Syntax-level failures — a different class of problem from semantic
/// validation failures (which produce a ValidationReport instead).
pub const DecodeError = error{
    UnexpectedToken,
    UnexpectedEndOfInput,
    InvalidSyntax,
    Overflow,
    OutOfMemory,
    // serval-r4h
    UnknownField,
    MissingRequiredField,
    InvalidEnumTag,
    // serval-x09: streaming source failed mid-decode.
    ReadFailed,
    // serval-tsm: untagged union input matched >1 variant under the
    // .unambiguous policy.
    AmbiguousUnion,
};
