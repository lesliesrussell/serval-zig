// serval-15q
//! serval-json: JSON backend. First format; bootstrapped on std.json,
//! to be replaced by a schema-driven decoder as the codec pipeline lands.

pub const json = @import("json.zig");
pub const decode = json.decode;
pub const encodeAlloc = json.encodeAlloc;
pub const DecodeOptions = json.DecodeOptions;
pub const EncodeOptions = json.EncodeOptions;
