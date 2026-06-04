// serval-15q
//! V1 rule taxonomy: scalar, string, collection, presence.

pub const Scalar = struct {
    min: ?i64 = null,
    max: ?i64 = null,
    gt: ?i64 = null,
    lt: ?i64 = null,
};

pub const String = struct {
    min_len: ?usize = null,
    max_len: ?usize = null,
    pattern: ?[]const u8 = null,
    email: bool = false,
    url: bool = false,
};

pub const Collection = struct {
    min_items: ?usize = null,
    max_items: ?usize = null,
    unique: bool = false,
};

pub const Presence = struct {
    required: bool = true,
    nonempty: bool = false,
};
