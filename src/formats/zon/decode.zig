// serval-9kw
//! ZON decode via std.zon.parse, with serval validation integrated.
//! Pass an arena (and .memory = .arena) — std.zon allocates result data
//! with the given allocator and the input is copied for sentinel
//! termination.

const std = @import("std");
const core = @import("serval-core");
const codec = @import("serval-codec");
const validate = @import("serval-validate");

pub const Error = core.DecodeError || error{ValidationFailed};

/// Typed fast path; see decodeResult for the report-carrying pipeline.
pub fn decode(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) Error!T {
    const result = try decodeResult(T, allocator, input, options);
    switch (result) {
        .ok => |ok| {
            allocator.free(ok.warnings.issues);
            allocator.free(ok.unknown);
            return ok.value;
        },
        .invalid => |report| {
            defer allocator.free(report.issues);
            return error.ValidationFailed;
        },
        .decode_error => |e| return e,
    }
}

pub fn decodeResult(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    options: codec.DecodeOptions,
) error{OutOfMemory}!core.DecodeResult(T) {
    const src = allocator.dupeZ(u8, input) catch return error.OutOfMemory;
    defer allocator.free(src);

    const value = std.zon.parse.fromSliceAlloc(T, allocator, src, null, .{
        .ignore_unknown_fields = options.unknown_fields != .reject,
        .free_on_error = options.memory != .arena,
    }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        // Bootstrap: std.zon folds syntax and shape failures together.
        error.ParseZon => return .{ .decode_error = error.InvalidSyntax },
    };

    if (options.validation != .none) {
        const report = validate.check(T, &value, allocator, .{}) catch return error.OutOfMemory;
        if (!report.ok()) {
            if (options.validation == .lax) {
                return .{ .ok = .{ .value = value, .warnings = report } };
            }
            return .{ .invalid = report };
        }
        allocator.free(report.issues);
    }

    return .{ .ok = .{ .value = value } };
}
