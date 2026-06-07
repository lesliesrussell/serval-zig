// serval-15q
//! Type-level policy knobs referenced from `pub const serval = .{ ... }`
//! metadata declarations.

pub const RenameRule = enum {
    none,
    snake_case,
    camel_case,
    pascal_case,
    kebab_case,
};

/// How `[]const u8` is treated on the wire.
pub const BytesPolicy = enum {
    string,
    bytes,
};

pub const EnumTagging = enum {
    name,
    value,
};

pub const UnionTagging = enum {
    external,
    internal,
    adjacent,
    untagged,
};

// serval-tsm
/// How untagged unions resolve when input could match several variants.
pub const UntaggedPolicy = enum {
    /// Declaration order wins (default) — order variants most→least
    /// specific.
    first_match,
    /// Try every variant; more than one match is error.AmbiguousUnion.
    unambiguous,
};
