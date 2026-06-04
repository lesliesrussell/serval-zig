// serval-15q
//! Per-field metadata attached via the `pub const serval = .{ .fields = ... }`
//! declaration on a type.

pub const FieldMeta = struct {
    rename: ?[]const u8 = null,
    required: bool = true,
    // Scalar rules
    min: ?i64 = null,
    max: ?i64 = null,
    gt: ?i64 = null,
    lt: ?i64 = null,
    // String rules
    min_len: ?usize = null,
    max_len: ?usize = null,
    pattern: ?[]const u8 = null,
    email: bool = false,
    url: bool = false,
    // Collection rules
    min_items: ?usize = null,
    max_items: ?usize = null,
    unique: bool = false,
};
