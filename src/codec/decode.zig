// serval-15q
//! Format-agnostic decode plumbing shared by backends.

const std = @import("std");
const core = @import("serval-core");
const options = @import("options.zig");
// serval-4tr
const validate = @import("serval-validate");

pub const DecodeOptions = options.DecodeOptions;

// serval-plc
/// Map a dynamic core.Value onto a typed T. Format-neutral: backends buffer
/// a value tree (e.g. for position-independent union tags) and finish here.
/// Lenient on unknown object keys; strings are reused from the Value tree
/// (ownership flows to the result). Container allocations in the source
/// tree become garbage after mapping — use an arena.
pub fn fromValue(
    comptime T: type,
    allocator: std.mem.Allocator,
    v: core.Value,
) core.DecodeError!T {
    return fromValueOpts(T, allocator, v, .{}, .none);
}

// serval-4tr
/// fromValue with a coercion mode (see validate.CoercionMode).
pub fn fromValueCoerce(
    comptime T: type,
    allocator: std.mem.Allocator,
    v: core.Value,
    mode: validate.CoercionMode,
) core.DecodeError!T {
    return fromValueOpts(T, allocator, v, .{}, mode);
}

// serval-plc
pub fn fromValueOpts(
    comptime T: type,
    allocator: std.mem.Allocator,
    v: core.Value,
    comptime parent: core.TypeOptions,
    mode: validate.CoercionMode,
) core.DecodeError!T {
    switch (@typeInfo(T)) {
        // serval-4tr: scalar branches accept coerced Values per mode.
        .bool => return switch (v) {
            .bool => |b| b,
            .string => |s| if (mode != .none)
                validate.coercion.boolFromString(s) orelse error.UnexpectedToken
            else
                error.UnexpectedToken,
            .int => |n| if (mode == .aggressive)
                validate.coercion.boolFromInt(n) orelse error.UnexpectedToken
            else
                error.UnexpectedToken,
            else => error.UnexpectedToken,
        },
        .int => return switch (v) {
            .int => |n| std.math.cast(T, n) orelse error.Overflow,
            .string => |s| if (mode != .none)
                validate.coercion.intFromString(T, s) orelse error.UnexpectedToken
            else
                error.UnexpectedToken,
            .float => |f| if (mode == .aggressive)
                validate.coercion.intFromFloat(T, f) orelse error.Overflow
            else
                error.UnexpectedToken,
            .bool => |b| if (mode == .aggressive)
                @intFromBool(b)
            else
                error.UnexpectedToken,
            else => error.UnexpectedToken,
        },
        .float => return switch (v) {
            .float => |f| @floatCast(f),
            .int => |n| @floatFromInt(n),
            .string => |s| if (mode != .none)
                validate.coercion.floatFromString(T, s) orelse error.UnexpectedToken
            else
                error.UnexpectedToken,
            else => error.UnexpectedToken,
        },
        .optional => |o| return switch (v) {
            .null => null,
            else => try fromValueOpts(o.child, allocator, v, parent, mode),
        },
        .@"enum" => switch (parent.enum_tagging) {
            .name => return switch (v) {
                .string => |s| std.meta.stringToEnum(T, s) orelse error.InvalidEnumTag,
                else => error.UnexpectedToken,
            },
            .value => return switch (v) {
                .int => |n| std.enums.fromInt(T, n) orelse error.InvalidEnumTag,
                else => error.UnexpectedToken,
            },
        },
        .pointer => |p| {
            if (p.size != .slice)
                @compileError("serval-codec: unsupported pointer type " ++ @typeName(T));
            if (p.child == u8 and parent.bytes_policy == .string) {
                return switch (v) {
                    .string, .bytes => |s| s,
                    // serval-4tr
                    .int => |n| if (mode == .aggressive)
                        std.fmt.allocPrint(allocator, "{d}", .{n}) catch error.OutOfMemory
                    else
                        error.UnexpectedToken,
                    .float => |f| if (mode == .aggressive)
                        std.fmt.allocPrint(allocator, "{d}", .{f}) catch error.OutOfMemory
                    else
                        error.UnexpectedToken,
                    .bool => |b| if (mode == .aggressive)
                        @as([]const u8, if (b) "true" else "false")
                    else
                        error.UnexpectedToken,
                    else => error.UnexpectedToken,
                };
            }
            const items = switch (v) {
                .array => |a| a,
                else => return error.UnexpectedToken,
            };
            const out = allocator.alloc(p.child, items.len) catch return error.OutOfMemory;
            for (items, out) |item, *slot| {
                slot.* = try fromValueOpts(p.child, allocator, item, parent, mode);
            }
            return out;
        },
        .@"struct" => {
            // serval-2si
            if (comptime core.isMap(T)) {
                const obj = switch (v) {
                    .object => |o| o,
                    else => return error.UnexpectedToken,
                };
                const entries = allocator.alloc(T.Entry, obj.len) catch return error.OutOfMemory;
                for (obj, entries) |fv, *slot| {
                    slot.* = .{ .key = fv.name, .value = try fromValueOpts(T.ValueType, allocator, fv.value, parent, mode) };
                }
                return .{ .entries = entries };
            }
            return fromValueStruct(T, allocator, v, mode);
        },
        .@"union" => return fromValueUnion(T, allocator, v, mode),
        else => @compileError("serval-codec: unsupported type " ++ @typeName(T)),
    }
}

// serval-plc
fn fromValueStruct(
    comptime T: type,
    allocator: std.mem.Allocator,
    v: core.Value,
    mode: validate.CoercionMode,
) core.DecodeError!T {
    const obj = switch (v) {
        .object => |o| o,
        else => return error.UnexpectedToken,
    };
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;
    inline for (S.fields, struct_fields) |sf, zf| {
        const found: ?core.Value = blk: {
            for (obj) |fv| {
                if (std.mem.eql(u8, fv.name, sf.wire_name)) break :blk fv.value;
            }
            break :blk null;
        };
        if (found) |fval| {
            @field(result, zf.name) = try fromValueOpts(zf.type, allocator, fval, S.options, mode);
            // serval-au2
            try validate.coercion.applyStringTransforms(sf.meta, zf.type, &@field(result, zf.name), allocator);
        } else if (zf.defaultValue()) |default| {
            @field(result, zf.name) = default;
        } else if (@typeInfo(zf.type) == .optional) {
            @field(result, zf.name) = null;
        } else {
            return error.MissingRequiredField;
        }
    }
    return result;
}

// serval-plc
fn fromValueUnion(
    comptime T: type,
    allocator: std.mem.Allocator,
    v: core.Value,
    mode: validate.CoercionMode,
) core.DecodeError!T {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval-codec: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    switch (comptime opts.union_tagging) {
        .external => switch (v) {
            // unit variant as bare string
            .string => |s| {
                inline for (info.fields) |f| {
                    const wire = comptime core.naming.convert(opts.rename_all, f.name);
                    if (f.type == void) {
                        if (std.mem.eql(u8, s, wire)) return @unionInit(T, f.name, {});
                    }
                }
                return error.InvalidEnumTag;
            },
            .object => |obj| {
                if (obj.len != 1) return error.UnexpectedToken;
                inline for (info.fields) |f| {
                    const wire = comptime core.naming.convert(opts.rename_all, f.name);
                    if (std.mem.eql(u8, obj[0].name, wire)) {
                        if (f.type == void) {
                            return switch (obj[0].value) {
                                .null => @unionInit(T, f.name, {}),
                                else => error.UnexpectedToken,
                            };
                        }
                        return @unionInit(T, f.name, try fromValueOpts(f.type, allocator, obj[0].value, .{}, mode));
                    }
                }
                return error.InvalidEnumTag;
            },
            else => return error.UnexpectedToken,
        },
        .adjacent => {
            const obj = switch (v) {
                .object => |o| o,
                else => return error.UnexpectedToken,
            };
            const tag: []const u8 = blk: {
                for (obj) |fv| {
                    if (std.mem.eql(u8, fv.name, opts.union_tag_field)) {
                        switch (fv.value) {
                            .string => |s| break :blk s,
                            else => return error.UnexpectedToken,
                        }
                    }
                }
                return error.UnexpectedToken;
            };
            inline for (info.fields) |f| {
                const wire = comptime core.naming.convert(opts.rename_all, f.name);
                if (std.mem.eql(u8, tag, wire)) {
                    if (f.type == void) return @unionInit(T, f.name, {});
                    for (obj) |fv| {
                        if (std.mem.eql(u8, fv.name, opts.union_content_field)) {
                            return @unionInit(T, f.name, try fromValueOpts(f.type, allocator, fv.value, .{}, mode));
                        }
                    }
                    return error.UnexpectedToken;
                }
            }
            return error.InvalidEnumTag;
        },
        .internal => {
            const obj = switch (v) {
                .object => |o| o,
                else => return error.UnexpectedToken,
            };
            const tag: []const u8 = blk: {
                for (obj) |fv| {
                    if (std.mem.eql(u8, fv.name, opts.union_tag_field)) {
                        switch (fv.value) {
                            .string => |s| break :blk s,
                            else => return error.UnexpectedToken,
                        }
                    }
                }
                return error.UnexpectedToken;
            };
            inline for (info.fields) |f| {
                const wire = comptime core.naming.convert(opts.rename_all, f.name);
                if (std.mem.eql(u8, tag, wire)) {
                    if (f.type == void) return @unionInit(T, f.name, {});
                    if (@typeInfo(f.type) != .@"struct")
                        @compileError("serval-codec: internal union tagging requires struct or void payloads: " ++ @typeName(T));
                    // Whole object passed through: the tag key is ignored as
                    // an unknown by the lenient struct mapper.
                    return @unionInit(T, f.name, try fromValueStruct(f.type, allocator, v, mode));
                }
            }
            return error.InvalidEnumTag;
        },
        .untagged => switch (comptime opts.untagged_policy) {
            // First variant (declaration order) that maps wins — order
            // types from most to least specific.
            .first_match => {
                inline for (info.fields) |f| {
                    if (f.type == void) {
                        if (v == .null) return @unionInit(T, f.name, {});
                    } else {
                        const attempt: ?f.type = fromValueOpts(f.type, allocator, v, .{}, mode) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            else => null,
                        };
                        if (attempt) |payload| return @unionInit(T, f.name, payload);
                    }
                }
                return error.InvalidEnumTag;
            },
            // serval-tsm: every variant is tried; >1 match is ambiguity.
            // Trial decodes allocate garbage per attempt — arena
            // recommended (same caveat as buffered unions generally).
            .unambiguous => {
                var result: ?T = null;
                var matches: usize = 0;
                inline for (info.fields) |f| {
                    if (f.type == void) {
                        if (v == .null) {
                            matches += 1;
                            if (result == null) result = @unionInit(T, f.name, {});
                        }
                    } else {
                        const attempt: ?f.type = fromValueOpts(f.type, allocator, v, .{}, mode) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            else => null,
                        };
                        if (attempt) |payload| {
                            matches += 1;
                            if (result == null) result = @unionInit(T, f.name, payload);
                        }
                    }
                }
                if (matches > 1) return error.AmbiguousUnion;
                return result orelse error.InvalidEnumTag;
            },
        },
    }
}
