// serval-15q
//! Thin classification layer over @typeInfo for schema inspection.

const std = @import("std");

pub const Kind = enum {
    bool,
    int,
    float,
    @"enum",
    optional,
    slice,
    array,
    @"struct",
    @"union",
    pointer,
    other,
};

pub fn kindOf(comptime T: type) Kind {
    return switch (@typeInfo(T)) {
        .bool => .bool,
        .int, .comptime_int => .int,
        .float, .comptime_float => .float,
        .@"enum" => .@"enum",
        .optional => .optional,
        .array => .array,
        .@"struct" => .@"struct",
        .@"union" => .@"union",
        .pointer => |p| if (p.size == .slice) .slice else .pointer,
        else => .other,
    };
}
