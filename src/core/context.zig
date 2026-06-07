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
    // serval-sru / serval-47j
    /// Segments pushed by walkers/decoders while descending into nested
    /// containers; issue() prepends them to each issue's leaf path.
    /// Inline buffer keeps shallow descent (≤16 levels) allocation-free —
    /// the zero-alloc borrowed guarantee covers nested structs; deeper
    /// nesting spills to the heap.
    path_buf: [16]errors.PathSegment = undefined,
    path_len: usize = 0,
    path_overflow: std.ArrayList(errors.PathSegment) = .empty,

    pub fn init(allocator: std.mem.Allocator) ValidateContext {
        return .{ .allocator = allocator, .issues = .empty };
    }

    pub fn deinit(self: *ValidateContext) void {
        // serval-sru
        for (self.issues.items) |i| self.allocator.free(i.path.segments);
        self.issues.deinit(self.allocator);
        self.path_overflow.deinit(self.allocator);
    }

    // serval-sru / serval-47j
    pub fn pushPath(self: *ValidateContext, seg: errors.PathSegment) void {
        if (self.path_overflow.items.len == 0 and self.path_len < self.path_buf.len) {
            self.path_buf[self.path_len] = seg;
            self.path_len += 1;
            return;
        }
        if (self.path_overflow.items.len == 0) {
            self.path_overflow.appendSlice(self.allocator, self.path_buf[0..self.path_len]) catch
                @panic("OOM pushing validation path");
        }
        self.path_overflow.append(self.allocator, seg) catch @panic("OOM pushing validation path");
        self.path_len += 1;
    }

    // serval-sru
    pub fn popPath(self: *ValidateContext) void {
        self.path_len -= 1;
        if (self.path_overflow.items.len > 0) _ = self.path_overflow.pop();
    }

    // serval-47j
    fn currentPath(self: *const ValidateContext) []const errors.PathSegment {
        if (self.path_overflow.items.len > 0) return self.path_overflow.items;
        return self.path_buf[0..self.path_len];
    }

    /// Records an issue. The current path stack is prepended to the
    /// issue's own (leaf) path; the combined path is allocator-owned.
    pub fn issue(self: *ValidateContext, i: errors.ValidationIssue) void {
        // serval-sru
        const prefix = self.currentPath();
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
