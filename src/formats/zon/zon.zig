// serval-9kw
//! ZON entry points conforming to the serval-codec backend contract.

const codec = @import("serval-codec");

pub const DecodeOptions = codec.DecodeOptions;
pub const EncodeOptions = codec.EncodeOptions;

pub const decode = @import("decode.zig").decode;
pub const decodeFromSlice = @import("decode.zig").decode;
pub const decodeResult = @import("decode.zig").decodeResult;
pub const encodeAlloc = @import("encode.zig").encodeAlloc;
pub const encodeToSlice = @import("encode.zig").encodeAlloc;

comptime {
    codec.codec.assertBackend(@This());
}
