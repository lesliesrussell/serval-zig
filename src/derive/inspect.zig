// serval-15q
//! Inspection helpers layered over serval-core schema reflection.

const core = @import("serval-core");

/// Whether T carries serval metadata (`pub const serval` or
/// `pub const serval_schema`).
pub fn hasMetadata(comptime T: type) bool {
    return core.schema.hasMeta(T);
}

pub const schemaOf = core.schemaOf;
