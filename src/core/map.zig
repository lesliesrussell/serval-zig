// serval-2si
//! String-keyed map type the codecs understand natively — for wire shapes
//! with arbitrary keys (OpenAPI paths, env blocks, label sets).
//!
//! Representation is an association slice: arena-friendly, zero hashing,
//! and ORDER-PRESERVING — entry order is part of the value, so canonical
//! encoding does not reorder map entries (determinism holds: same value,
//! same bytes). Lookups are linear; this is a wire-shape type, not a
//! general-purpose container.

const std = @import("std");

pub fn Map(comptime V: type) type {
    return struct {
        const Self = @This();

        /// Marker for codec detection — see isMap().
        pub const is_serval_map = true;
        pub const ValueType = V;
        pub const Entry = struct {
            key: []const u8,
            value: V,
        };

        entries: []const Entry = &.{},

        pub fn get(self: Self, key: []const u8) ?V {
            for (self.entries) |e| {
                if (std.mem.eql(u8, e.key, key)) return e.value;
            }
            return null;
        }

        pub fn count(self: Self) usize {
            return self.entries.len;
        }
    };
}

pub fn isMap(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and
        @hasDecl(T, "is_serval_map") and T.is_serval_map;
}
