// serval-15q
//! Mutable context handed to validators; collects issues into a report.

const std = @import("std");
const errors = @import("errors.zig");

pub const ValidateContext = struct {
    allocator: std.mem.Allocator,
    issues: std.ArrayList(errors.ValidationIssue),
    // serval-r4h
    /// Zig field names present in the decoded input (top level).
    /// Populated by the decode pipeline; empty for standalone check().
    present_fields: []const []const u8 = &.{},

    pub fn init(allocator: std.mem.Allocator) ValidateContext {
        return .{ .allocator = allocator, .issues = .empty };
    }

    pub fn deinit(self: *ValidateContext) void {
        self.issues.deinit(self.allocator);
    }

    pub fn issue(self: *ValidateContext, i: errors.ValidationIssue) void {
        self.issues.append(self.allocator, i) catch @panic("OOM collecting validation issue");
    }

    // serval-r4h
    /// Whether the named field was present in the decoded input.
    /// Always false outside the decode pipeline.
    pub fn has(self: *const ValidateContext, field_name: []const u8) bool {
        for (self.present_fields) |p| {
            if (std.mem.eql(u8, p, field_name)) return true;
        }
        return false;
    }

    pub fn report(self: *const ValidateContext) errors.ValidationReport {
        return .{ .issues = self.issues.items };
    }
};
