// serval-15q
//! Path types live in serval-core (the core owns pathing); this module
//! re-exports them and will grow runtime path-builder helpers.

const core = @import("serval-core");

pub const Path = core.Path;
pub const Segment = core.PathSegment;
