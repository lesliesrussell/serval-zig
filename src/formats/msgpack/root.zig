// serval-bfi
//! serval-msgpack: MessagePack backend, wire format implemented in-tree.
//! Schema-driven both directions like serval-json: wire names, bytes/enum
//! policies (bytes_policy maps to native str vs bin), all four union
//! tagging modes, presence tracking, borrowed mode. Ext types unsupported.

pub const msgpack = @import("msgpack.zig");
pub const capabilities = msgpack.capabilities;
pub const decode = msgpack.decode;
pub const decodeResult = msgpack.decodeResult;
pub const decodeBorrowed = msgpack.decodeBorrowed;
// serval-l3p
pub const decodeValue = msgpack.decodeValue;
pub const decodeFromReader = msgpack.decodeFromReader;
pub const decodeProjection = msgpack.decodeProjection;
pub const encodeAlloc = msgpack.encodeAlloc;
pub const encodeToWriter = msgpack.encodeToWriter;
pub const measureEncodedLen = msgpack.measureEncodedLen;
pub const DecodeOptions = msgpack.DecodeOptions;
pub const EncodeOptions = msgpack.EncodeOptions;
