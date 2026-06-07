// serval-15q
//! serval-json: JSON backend. First format; bootstrapped on std.json,
//! to be replaced by a schema-driven decoder as the codec pipeline lands.

pub const json = @import("json.zig");
// serval-xx5
pub const capabilities = json.capabilities;
pub const decode = json.decode;
// serval-r4h
pub const decodeResult = json.decodeResult;
// serval-0mq
pub const decodeBorrowed = json.decodeBorrowed;
// serval-l3p
pub const decodeValue = json.decodeValue;
// serval-x09
pub const decodeFromReader = json.decodeFromReader;
// serval-54c
pub const decodeProjection = json.decodeProjection;
pub const decodeResultFromReader = json.decodeResultFromReader;
pub const encodeToWriter = json.encodeToWriter;
pub const measureEncodedLen = json.measureEncodedLen;
pub const encodeAlloc = json.encodeAlloc;
pub const DecodeOptions = json.DecodeOptions;
pub const EncodeOptions = json.EncodeOptions;
