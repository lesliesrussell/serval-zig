// serval-4am
//! Field-name rename rules — implementation lives in serval-core (the
//! schema builder needs it); re-exported here for derive-layer consumers.

const core = @import("serval-core");

pub const convert = core.naming.convert;
