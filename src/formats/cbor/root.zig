// serval-7jg
//! serval-cbor: CBOR (RFC 8949) backend, wire format implemented in-tree.
//! Schema-driven both directions like serval-json/msgpack: wire names,
//! bytes/enum policies (bytes_policy maps to text vs byte strings), all
//! four union tagging modes, presence tracking, borrowed mode.
//! v1 limits: definite lengths only (indefinite items rejected), tags
//! (major type 6) rejected, f16 decoded but never emitted.

pub const cbor = @import("cbor.zig");
pub const decode = cbor.decode;
pub const decodeResult = cbor.decodeResult;
pub const decodeBorrowed = cbor.decodeBorrowed;
pub const decodeFromReader = cbor.decodeFromReader;
pub const decodeValue = cbor.decodeValue;
pub const encodeAlloc = cbor.encodeAlloc;
pub const encodeToWriter = cbor.encodeToWriter;
pub const measureEncodedLen = cbor.measureEncodedLen;
pub const DecodeOptions = cbor.DecodeOptions;
pub const EncodeOptions = cbor.EncodeOptions;
