// serval-15q
//! Comptime-generated structural metadata for Zig types.
//! Customization comes from an explicit `pub const serval = .{ ... }`
//! declaration adjacent to the type (Zig has no attributes).

const std = @import("std");
const attributes = @import("attributes.zig");
const field_meta = @import("field_meta.zig");
const naming = @import("naming.zig");

// serval-4am
pub const Field = struct {
    name: []const u8,
    /// Resolved wire name: explicit `.rename` if given, else the
    /// rename_all policy applied to the Zig field name.
    wire_name: []const u8,
    is_optional: bool = false,
    has_default: bool = false,
    meta: field_meta.FieldMeta = .{},
};

pub const TypeOptions = struct {
    rename_all: attributes.RenameRule = .none,
    bytes_policy: attributes.BytesPolicy = .string,
    enum_tagging: attributes.EnumTagging = .name,
    union_tagging: attributes.UnionTagging = .external,
    // serval-x9g
    /// Key names for .adjacent (and future .internal) union tagging.
    union_tag_field: []const u8 = "type",
    union_content_field: []const u8 = "content",
    // serval-tsm
    untagged_policy: attributes.UntaggedPolicy = .first_match,
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

// serval-gy5
/// Metadata may be declared as `pub const serval` or — because that name
/// shadows the conventional import alias inside hook functions — as
/// `pub const serval_schema`. Declaring both is a compile error.
pub fn hasMeta(comptime T: type) bool {
    return @hasDecl(T, "serval") or @hasDecl(T, "serval_schema");
}

// serval-gy5
fn MetaType(comptime T: type) type {
    if (@hasDecl(T, "serval")) return @TypeOf(T.serval);
    return @TypeOf(T.serval_schema);
}

// serval-gy5
pub fn metaOf(comptime T: type) MetaType(T) {
    if (@hasDecl(T, "serval")) {
        if (@hasDecl(T, "serval_schema"))
            @compileError("declare either 'serval' or 'serval_schema' metadata on " ++ @typeName(T) ++ ", not both");
        return T.serval;
    }
    return T.serval_schema;
}

// serval-4am
fn collectFields(comptime T: type) []const Field {
    comptime {
        const info = @typeInfo(T);
        if (info != .@"struct") return &.{};
        verifyMetadataFieldKeys(T);
        const opts = collectOptions(T);
        const struct_fields = info.@"struct".fields;
        var out: [struct_fields.len]Field = undefined;
        for (struct_fields, 0..) |f, i| {
            const meta = fieldMetaFor(T, f.name);
            out[i] = .{
                .name = f.name,
                .wire_name = meta.rename orelse naming.convert(opts.rename_all, f.name),
                .is_optional = @typeInfo(f.type) == .optional,
                .has_default = f.default_value_ptr != null,
                .meta = meta,
            };
        }
        const final = out;
        return &final;
    }
}

// serval-4am
fn collectOptions(comptime T: type) TypeOptions {
    comptime {
        if (@typeInfo(T) != .@"struct" and @typeInfo(T) != .@"union" and @typeInfo(T) != .@"enum")
            return .{};
        if (!hasMeta(T)) return .{};
        const m = metaOf(T);
        var out: TypeOptions = .{};
        for (@typeInfo(@TypeOf(m)).@"struct".fields) |f| {
            if (std.mem.eql(u8, f.name, "fields")) continue;
            if (!@hasField(TypeOptions, f.name))
                @compileError("unknown serval option '." ++ f.name ++ "' on " ++ @typeName(T));
            @field(out, f.name) = @field(m, f.name);
        }
        return out;
    }
}

// serval-4am
fn fieldMetaFor(comptime T: type, comptime field_name: []const u8) field_meta.FieldMeta {
    comptime {
        if (!hasMeta(T)) return .{};
        const m = metaOf(T);
        if (!@hasField(@TypeOf(m), "fields")) return .{};
        const fs = m.fields;
        if (!@hasField(@TypeOf(fs), field_name)) return .{};
        return coerceInto(field_meta.FieldMeta, @field(fs, field_name), T);
    }
}

// serval-4am
fn verifyMetadataFieldKeys(comptime T: type) void {
    comptime {
        if (!hasMeta(T)) return;
        const m = metaOf(T);
        if (!@hasField(@TypeOf(m), "fields")) return;
        for (@typeInfo(@TypeOf(m.fields)).@"struct".fields) |mf| {
            if (!@hasField(T, mf.name))
                @compileError("serval metadata names field '." ++ mf.name ++
                    "' which does not exist on " ++ @typeName(T));
        }
    }
}

// serval-4am
fn coerceInto(comptime Target: type, comptime src: anytype, comptime Owner: type) Target {
    comptime {
        var out: Target = .{};
        for (@typeInfo(@TypeOf(src)).@"struct".fields) |f| {
            // serval-bmf: .validator is a comptime function value — it
            // can't live in the runtime FieldMeta struct; the validation
            // engine reads it straight from the metadata declaration.
            if (std.mem.eql(u8, f.name, "validator")) continue;
            if (!@hasField(Target, f.name))
                @compileError("unknown serval field rule '." ++ f.name ++ "' on " ++ @typeName(Owner));
            @field(out, f.name) = @field(src, f.name);
        }
        return out;
    }
}

// serval-bmf
/// The field's custom validator type from `pub const serval` metadata, or
/// null. Comptime-checked: must be `fn (*ValidateContext, *const FT) void`
/// (ValidateContext checked structurally by the call site).
pub fn fieldValidator(comptime T: type, comptime field_name: []const u8) ?type {
    comptime {
        if (@typeInfo(T) != .@"struct") return null;
        if (!hasMeta(T)) return null;
        const m = metaOf(T);
        if (!@hasField(@TypeOf(m), "fields")) return null;
        if (!@hasField(@TypeOf(m.fields), field_name)) return null;
        const fm = @field(m.fields, field_name);
        if (!@hasField(@TypeOf(fm), "validator")) return null;
        return struct {
            pub const f = @field(fm, "validator");
        };
    }
}
