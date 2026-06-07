// serval-9ov
//! JSON Schema (draft 2020-12) emission from Schema(T).
//!
//! Mapping table (constraints → keywords):
//!   min/max → minimum/maximum (merged with integer type bounds when the
//!   type is ≤32 bits; wider bounds exceed JSON number precision and are
//!   omitted) · gt/lt → exclusiveMinimum/exclusiveMaximum · one_of /
//!   one_of_str / enum tags → enum · min_len/max_len → minLength/maxLength
//!   · nonempty → minLength/minItems 1 (when unset) · pattern → pattern
//!   (anchored "^(?:…)$" when pattern_full; search semantics otherwise,
//!   matching ECMA regex defaults) · email → format:"email" · url →
//!   format:"uri" · min_items/max_items → minItems/maxItems · unique →
//!   uniqueItems · defaults → default (encoded via serval-json) ·
//!   additionalProperties:false (serval's default unknown_fields=.reject).
//! Unmappable (documented, silently skipped): .trim/.lowercase transforms,
//! .validator functions, servalValidate hooks, coercion modes.
//! Nested structs inline (serval types are non-recursive); no $defs.

const std = @import("std");
const core = @import("serval-core");
const json = @import("serval-json");

const Writer = std.Io.Writer;

/// Emit a draft 2020-12 JSON Schema document for T. Caller frees.
pub fn jsonSchema(comptime T: type, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
    var aw: Writer.Allocating = .init(allocator);
    defer aw.deinit();
    jsonSchemaToWriter(T, &aw.writer) catch return error.OutOfMemory;
    return aw.toOwnedSlice();
}

pub fn jsonSchemaToWriter(comptime T: type, w: *Writer) Writer.Error!void {
    try w.writeAll("{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",");
    try writeInner(T, .{}, .{}, w);
    try w.writeByte('}');
}

fn jstr(w: *Writer, s: []const u8) Writer.Error!void {
    try std.json.Stringify.encodeJsonString(s, .{}, w);
}

/// Emits the node's keywords WITHOUT surrounding braces, so call sites
/// can append siblings like "default".
fn writeInner(
    comptime T: type,
    comptime meta: core.FieldMeta,
    comptime parent: core.TypeOptions,
    w: *Writer,
) Writer.Error!void {
    switch (@typeInfo(T)) {
        .bool => try w.writeAll("\"type\":\"boolean\""),
        .int => {
            try w.writeAll("\"type\":\"integer\"");
            const bounded = @bitSizeOf(T) <= 32;
            const minimum: ?i128 = comptime blk: {
                const t: ?i128 = if (bounded) std.math.minInt(T) else null;
                if (meta.min) |m| break :blk @max(m, t orelse m);
                break :blk t;
            };
            const maximum: ?i128 = comptime blk: {
                const t: ?i128 = if (bounded) std.math.maxInt(T) else null;
                if (meta.max) |m| break :blk @min(m, t orelse m);
                break :blk t;
            };
            if (minimum) |m| try w.print(",\"minimum\":{d}", .{m});
            if (maximum) |m| try w.print(",\"maximum\":{d}", .{m});
            if (meta.gt) |g| try w.print(",\"exclusiveMinimum\":{d}", .{g});
            if (meta.lt) |l| try w.print(",\"exclusiveMaximum\":{d}", .{l});
            if (meta.one_of) |allowed| {
                try w.writeAll(",\"enum\":[");
                for (allowed, 0..) |a, i| {
                    if (i != 0) try w.writeByte(',');
                    try w.print("{d}", .{a});
                }
                try w.writeByte(']');
            }
        },
        .float => {
            try w.writeAll("\"type\":\"number\"");
            if (meta.min) |m| try w.print(",\"minimum\":{d}", .{m});
            if (meta.max) |m| try w.print(",\"maximum\":{d}", .{m});
            if (meta.gt) |g| try w.print(",\"exclusiveMinimum\":{d}", .{g});
            if (meta.lt) |l| try w.print(",\"exclusiveMaximum\":{d}", .{l});
        },
        .@"enum" => |e| {
            try w.writeAll("\"enum\":[");
            inline for (e.fields, 0..) |f, i| {
                if (i != 0) try w.writeByte(',');
                switch (parent.enum_tagging) {
                    .name => try jstr(w, f.name),
                    .value => try w.print("{d}", .{f.value}),
                }
            }
            try w.writeByte(']');
        },
        .optional => |o| {
            try w.writeAll("\"anyOf\":[{");
            try writeInner(o.child, meta, parent, w);
            try w.writeAll("},{\"type\":\"null\"}]");
        },
        .pointer => |p| {
            if (p.size != .slice)
                @compileError("serval schema export: unsupported pointer type " ++ @typeName(T));
            if (p.child == u8 and parent.bytes_policy == .string) {
                try w.writeAll("\"type\":\"string\"");
                const min_len: ?usize = meta.min_len orelse if (meta.nonempty) 1 else null;
                if (min_len) |m| try w.print(",\"minLength\":{d}", .{m});
                if (meta.max_len) |m| try w.print(",\"maxLength\":{d}", .{m});
                if (meta.pattern) |pat| {
                    try w.writeAll(",\"pattern\":");
                    if (meta.pattern_full) {
                        try jstr(w, "^(?:" ++ pat ++ ")$");
                    } else {
                        try jstr(w, pat);
                    }
                }
                if (meta.email) try w.writeAll(",\"format\":\"email\"");
                if (meta.url) try w.writeAll(",\"format\":\"uri\"");
                if (meta.one_of_str) |allowed| {
                    try w.writeAll(",\"enum\":[");
                    for (allowed, 0..) |a, i| {
                        if (i != 0) try w.writeByte(',');
                        try jstr(w, a);
                    }
                    try w.writeByte(']');
                }
            } else if (p.child == u8) {
                try w.writeAll("\"type\":\"array\",\"items\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":255}");
            } else {
                try w.writeAll("\"type\":\"array\",\"items\":{");
                try writeInner(p.child, .{}, parent, w);
                try w.writeByte('}');
                const min_items: ?usize = meta.min_items orelse if (meta.nonempty) 1 else null;
                if (min_items) |m| try w.print(",\"minItems\":{d}", .{m});
                if (meta.max_items) |m| try w.print(",\"maxItems\":{d}", .{m});
                if (meta.unique) try w.writeAll(",\"uniqueItems\":true");
            }
        },
        .@"struct" => {
            // serval-2si: maps — value subschema via additionalProperties,
            // entry-count rules via min/maxProperties.
            if (comptime core.isMap(T)) {
                try w.writeAll("\"type\":\"object\",\"additionalProperties\":{");
                try writeInner(T.ValueType, .{}, .{}, w);
                try w.writeByte('}');
                const min_props: ?usize = meta.min_items orelse if (meta.nonempty) 1 else null;
                if (min_props) |m| try w.print(",\"minProperties\":{d}", .{m});
                if (meta.max_items) |m| try w.print(",\"maxProperties\":{d}", .{m});
                return;
            }
            try writeStructInner(T, w);
        },
        .@"union" => try writeUnionInner(T, w),
        else => @compileError("serval schema export: unsupported type " ++ @typeName(T)),
    }
}

fn writeStructInner(comptime T: type, w: *Writer) Writer.Error!void {
    const S = core.schemaOf(T);
    const struct_fields = @typeInfo(T).@"struct".fields;
    try w.writeAll("\"type\":\"object\",\"properties\":{");
    inline for (S.fields, struct_fields, 0..) |sf, zf, i| {
        if (i != 0) try w.writeByte(',');
        try jstr(w, sf.wire_name);
        try w.writeAll(":{");
        try writeInner(zf.type, sf.meta, S.options, w);
        if (zf.defaultValue()) |d| {
            try w.writeAll(",\"default\":");
            try json.encodeToWriter(zf.type, d, .{}, w);
        }
        try w.writeByte('}');
    }
    try w.writeAll("},\"required\":[");
    comptime var first = true;
    inline for (S.fields, struct_fields) |sf, zf| {
        if (comptime zf.defaultValue() == null and @typeInfo(zf.type) != .optional) {
            if (!first) try w.writeByte(',');
            first = false;
            try jstr(w, sf.wire_name);
        }
    }
    try w.writeAll("],\"additionalProperties\":false");
}

fn writeUnionInner(comptime T: type, w: *Writer) Writer.Error!void {
    const info = @typeInfo(T).@"union";
    if (info.tag_type == null)
        @compileError("serval schema export: untagged Zig unions unsupported: " ++ @typeName(T));
    const opts = core.schemaOf(T).options;
    try w.writeAll("\"oneOf\":[");
    inline for (info.fields, 0..) |f, i| {
        if (i != 0) try w.writeByte(',');
        const wire = comptime core.naming.convert(opts.rename_all, f.name);
        switch (opts.union_tagging) {
            .external => {
                if (f.type == void) {
                    try w.writeAll("{\"const\":");
                    try jstr(w, wire);
                    try w.writeByte('}');
                } else {
                    try w.writeAll("{\"type\":\"object\",\"properties\":{");
                    try jstr(w, wire);
                    try w.writeAll(":{");
                    try writeInner(f.type, .{}, .{}, w);
                    try w.writeAll("}},\"required\":[");
                    try jstr(w, wire);
                    try w.writeAll("],\"additionalProperties\":false}");
                }
            },
            .internal => {
                try w.writeAll("{\"type\":\"object\",\"properties\":{");
                try jstr(w, opts.union_tag_field);
                try w.writeAll(":{\"const\":");
                try jstr(w, wire);
                try w.writeByte('}');
                comptime var required: []const []const u8 = &.{opts.union_tag_field};
                if (f.type != void) {
                    if (@typeInfo(f.type) != .@"struct")
                        @compileError("serval schema export: internal tagging requires struct or void payloads: " ++ @typeName(T));
                    const PS = core.schemaOf(f.type);
                    const pfields = @typeInfo(f.type).@"struct".fields;
                    inline for (PS.fields, pfields) |sf, zf| {
                        try w.writeByte(',');
                        try jstr(w, sf.wire_name);
                        try w.writeAll(":{");
                        try writeInner(zf.type, sf.meta, PS.options, w);
                        if (zf.defaultValue()) |d| {
                            try w.writeAll(",\"default\":");
                            try json.encodeToWriter(zf.type, d, .{}, w);
                        }
                        try w.writeByte('}');
                        if (comptime zf.defaultValue() == null and @typeInfo(zf.type) != .optional) {
                            required = required ++ &[_][]const u8{sf.wire_name};
                        }
                    }
                }
                try w.writeAll("},\"required\":[");
                inline for (required, 0..) |r, ri| {
                    if (ri != 0) try w.writeByte(',');
                    try jstr(w, r);
                }
                try w.writeAll("],\"additionalProperties\":false}");
            },
            .adjacent => {
                try w.writeAll("{\"type\":\"object\",\"properties\":{");
                try jstr(w, opts.union_tag_field);
                try w.writeAll(":{\"const\":");
                try jstr(w, wire);
                try w.writeByte('}');
                if (f.type != void) {
                    try w.writeByte(',');
                    try jstr(w, opts.union_content_field);
                    try w.writeAll(":{");
                    try writeInner(f.type, .{}, .{}, w);
                    try w.writeByte('}');
                }
                try w.writeAll("},\"required\":[");
                try jstr(w, opts.union_tag_field);
                if (f.type != void) {
                    try w.writeByte(',');
                    try jstr(w, opts.union_content_field);
                }
                try w.writeAll("],\"additionalProperties\":false}");
            },
            .untagged => {
                if (f.type == void) {
                    try w.writeAll("{\"type\":\"null\"}");
                } else {
                    try w.writeByte('{');
                    try writeInner(f.type, .{}, .{}, w);
                    try w.writeByte('}');
                }
            },
        }
    }
    try w.writeByte(']');
}
