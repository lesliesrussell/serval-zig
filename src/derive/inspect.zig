// serval-15q
//! Inspection helpers layered over serval-core schema reflection.

const core = @import("serval-core");

/// Whether T carries a `pub const serval = .{ ... }` metadata declaration.
pub fn hasMetadata(comptime T: type) bool {
    return @hasDecl(T, "serval");
}

pub const schemaOf = core.schemaOf;
