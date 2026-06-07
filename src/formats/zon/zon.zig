// serval-9kw
//! ZON entry points conforming to the serval-codec backend contract.

const codec = @import("serval-codec");

pub const DecodeOptions = codec.DecodeOptions;
pub const EncodeOptions = codec.EncodeOptions;

// serval-xx5: the bootstrap gaps as machine-readable flags. Native Zig
// unions still roundtrip via std.zon's own syntax — "unsupported" means
// serval's tagging METADATA is not honored.
pub const capabilities: codec.Capabilities = .{
    .presence_tracking = false,
    .borrowed_mode = false,
    .coercion = false,
    .rename_metadata = false,
    .shape_issue_fidelity = false,
    .collect_unknown = false,
    .projection = false,
    .transforms = false,
    .union_external = .unsupported,
    .union_adjacent = .unsupported,
    .union_internal = .unsupported,
    .union_untagged = .unsupported,
};

pub const decode = @import("decode.zig").decode;
pub const decodeFromSlice = @import("decode.zig").decode;
pub const decodeResult = @import("decode.zig").decodeResult;
pub const encodeAlloc = @import("encode.zig").encodeAlloc;
pub const encodeToSlice = @import("encode.zig").encodeAlloc;
// serval-x09
pub const decodeFromReader = @import("decode.zig").decodeFromReader;
pub const encodeToWriter = @import("encode.zig").encodeToWriter;
pub const measureEncodedLen = @import("encode.zig").measureEncodedLen;

comptime {
    codec.codec.assertBackend(@This());
}
