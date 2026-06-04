// serval-15q
//! Comptime-generated structural metadata for Zig types.

const std = @import("std");
const attributes = @import("attributes.zig");

pub const Field = struct {
    name: []const u8,
    wire_name: ?[]const u8 = null,
    is_optional: bool = false,
    has_default: bool = false,
};

pub const TypeOptions = struct {
    rename_all: attributes.RenameRule = .none,
    bytes_policy: attributes.BytesPolicy = .string,
    enum_tagging: attributes.EnumTagging = .name,
    union_tagging: attributes.UnionTagging = .external,
};

pub fn Schema(comptime T: type) type {
    return struct {
        pub const zig_type = T;
        pub const fields: []const Field = collectFields(T);
        pub const options: TypeOptions = collectOptions(T);
    };
}

/// Entry point: `const S = serval.core.schemaOf(User);`
pub fn schemaOf(comptime T: type) type {
    return Schema(T);
}

fn collectFields(comptime T: type) []const Field {
    comptime {
        const info = @typeInfo(T);
        if (info != .@"struct") return &.{};
        const struct_fields = info.@"struct".fields;
        var out: [struct_fields.len]Field = undefined;
        for (struct_fields, 0..) |f, i| {
            out[i] = .{
                .name = f.name,
                .is_optional = @typeInfo(f.type) == .optional,
                .has_default = f.default_value_ptr != null,
            };
        }
        const final = out;
        return &final;
    }
}

fn collectOptions(comptime T: type) TypeOptions {
    // Reserved: parse the `pub const serval = .{ ... }` metadata declaration
    // (rename_all, per-field constraints) — see docs/architecture.md.
    if (@hasDecl(T, "serval")) return .{};
    return .{};
}
