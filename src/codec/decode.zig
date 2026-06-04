// serval-15q
//! Format-agnostic decode plumbing shared by backends.
//! Reserved: token-stream → typed-value mapping, presence tracking for
//! validation, unknown-field policy enforcement.

const options = @import("options.zig");

pub const DecodeOptions = options.DecodeOptions;
