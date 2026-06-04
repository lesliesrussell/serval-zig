// serval-15q
//! Mutable context handed to validators; collects issues into a report.

const std = @import("std");
const errors = @import("errors.zig");

pub const ValidateContext = struct {
    allocator: std.mem.Allocator,
    issues: std.ArrayList(errors.ValidationIssue),

    pub fn init(allocator: std.mem.Allocator) ValidateContext {
        return .{ .allocator = allocator, .issues = .empty };
    }

    pub fn deinit(self: *ValidateContext) void {
        self.issues.deinit(self.allocator);
    }

    pub fn issue(self: *ValidateContext, i: errors.ValidationIssue) void {
        self.issues.append(self.allocator, i) catch @panic("OOM collecting validation issue");
    }

    /// Whether the named field was present in the input.
    /// Reserved: presence tracking is wired up by the decode pipeline.
    pub fn has(self: *const ValidateContext, field_name: []const u8) bool {
        _ = self;
        _ = field_name;
        return false;
    }

    pub fn report(self: *const ValidateContext) errors.ValidationReport {
        return .{ .issues = self.issues.items };
    }
};
