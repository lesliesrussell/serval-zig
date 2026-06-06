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
    // serval-sru
    /// Segments pushed by walkers/decoders while descending into nested
    /// containers; issue() prepends them to each issue's leaf path.
    path_stack: std.ArrayList(errors.PathSegment) = .empty,

    pub fn init(allocator: std.mem.Allocator) ValidateContext {
        return .{ .allocator = allocator, .issues = .empty };
    }

    pub fn deinit(self: *ValidateContext) void {
        // serval-sru
        for (self.issues.items) |i| self.allocator.free(i.path.segments);
        self.issues.deinit(self.allocator);
        self.path_stack.deinit(self.allocator);
    }

    // serval-sru
    pub fn pushPath(self: *ValidateContext, seg: errors.PathSegment) void {
        self.path_stack.append(self.allocator, seg) catch @panic("OOM pushing validation path");
    }

    // serval-sru
    pub fn popPath(self: *ValidateContext) void {
        _ = self.path_stack.pop();
    }

    /// Records an issue. The current path stack is prepended to the
    /// issue's own (leaf) path; the combined path is allocator-owned.
    pub fn issue(self: *ValidateContext, i: errors.ValidationIssue) void {
        // serval-sru
        const prefix = self.path_stack.items;
        const segs = self.allocator.alloc(
            errors.PathSegment,
            prefix.len + i.path.segments.len,
        ) catch @panic("OOM collecting validation issue");
        @memcpy(segs[0..prefix.len], prefix);
        @memcpy(segs[prefix.len..], i.path.segments);
        var full = i;
        full.path = .{ .segments = segs };
        self.issues.append(self.allocator, full) catch @panic("OOM collecting validation issue");
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
