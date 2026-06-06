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

// serval-sru
/// Whether decoding/validating T can descend into struct fields (and so
/// produce nested-path issues). Gates path pushes so flat decodes stay
/// allocation-free.
pub fn containsStruct(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => true,
        .optional => |o| containsStruct(o.child),
        .pointer => |p| p.size == .slice and p.child != u8 and containsStruct(p.child),
        else => false,
    };
}

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
