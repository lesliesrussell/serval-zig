// serval-7jg
//! CBOR entry points conforming to the serval-codec backend contract.

const codec = @import("serval-codec");

pub const DecodeOptions = codec.DecodeOptions;
pub const EncodeOptions = codec.EncodeOptions;

pub const decode = @import("decode.zig").decode;
pub const decodeFromSlice = @import("decode.zig").decode;
pub const decodeResult = @import("decode.zig").decodeResult;
pub const decodeBorrowed = @import("decode.zig").decodeBorrowed;
pub const decodeFromReader = @import("decode.zig").decodeFromReader;
pub const decodeValue = @import("decode.zig").decodeValueSlice;
pub const encodeAlloc = @import("encode.zig").encodeAlloc;
pub const encodeToSlice = @import("encode.zig").encodeAlloc;
pub const encodeToWriter = @import("encode.zig").encodeToWriter;
pub const measureEncodedLen = @import("encode.zig").measureEncodedLen;

comptime {
    codec.codec.assertBackend(@This());
}
