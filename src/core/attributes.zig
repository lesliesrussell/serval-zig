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
