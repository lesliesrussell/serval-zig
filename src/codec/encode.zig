// serval-15q
//! Format-agnostic encode plumbing shared by backends.
//! Reserved: schema-driven field iteration, rename application,
//! bytes-policy handling.

const options = @import("options.zig");

pub const EncodeOptions = options.EncodeOptions;
