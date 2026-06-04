// serval-15q
//! Enum/union tagging strategy resolution.
//! Reserved: resolve per-type EnumTagging/UnionTagging from metadata and
//! generate the wire-name tables.

const core = @import("serval-core");

pub const EnumTagging = core.attributes.EnumTagging;
pub const UnionTagging = core.attributes.UnionTagging;
