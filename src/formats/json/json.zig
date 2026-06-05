// serval-15q
//! JSON entry points conforming to the serval-codec backend contract.

const std = @import("std");
const codec = @import("serval-codec");

pub const DecodeOptions = codec.DecodeOptions;
pub const EncodeOptions = codec.EncodeOptions;

pub const decode = @import("decode.zig").decode;
pub const decodeFromSlice = @import("decode.zig").decode;
// serval-r4h
pub const decodeResult = @import("decode.zig").decodeResult;
pub const encodeAlloc = @import("encode.zig").encodeAlloc;
pub const encodeToSlice = @import("encode.zig").encodeAlloc;

comptime {
    // Backend contract check.
    @import("serval-codec").codec.assertBackend(@This());
}
