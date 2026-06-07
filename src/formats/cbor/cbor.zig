// serval-2wi
//! CBOR entry points: codec.binary.Backend instantiated over the CBOR
//! wire layer. Conforms to the serval-codec backend contract.

const codec = @import("serval-codec");
const wire = @import("wire.zig");

const B = codec.binary.Backend(wire);

pub const DecodeOptions = codec.DecodeOptions;
pub const EncodeOptions = codec.EncodeOptions;
pub const Error = B.Error;

pub const capabilities = B.capabilities;
pub const decode = B.decode;
pub const decodeFromSlice = B.decode;
pub const decodeResult = B.decodeResult;
pub const decodeBorrowed = B.decodeBorrowed;
pub const decodeFromReader = B.decodeFromReader;
pub const decodeValue = B.decodeValueSlice;
pub const encodeAlloc = B.encodeAlloc;
pub const encodeToSlice = B.encodeAlloc;
pub const encodeToWriter = B.encodeToWriter;
pub const measureEncodedLen = B.measureEncodedLen;

comptime {
    codec.codec.assertBackend(@This());
}
