// serval-15q
//! serval-codec: reader/writer-facing encode/decode interfaces and
//! allocation strategies. Isolates evolving std.Io specifics from the
//! rest of the codebase.

pub const codec = @import("codec.zig");
// serval-2wi
pub const binary = @import("binary.zig");
pub const decode = @import("decode.zig");
pub const encode = @import("encode.zig");
pub const reader = @import("reader.zig");
pub const writer = @import("writer.zig");
pub const options = @import("options.zig");
pub const borrow = @import("borrow.zig");
pub const alloc = @import("alloc.zig");

pub const MemoryMode = options.MemoryMode;
// serval-plc
pub const fromValue = decode.fromValue;
// serval-xx5
pub const Capabilities = codec.Capabilities;
pub const UnionModeSupport = codec.UnionModeSupport;
// serval-sj2
pub const KeyOrder = codec.KeyOrder;
pub const sortedKeyIndices = codec.sortedKeyIndices;
// serval-47j
pub const zeroAllocEligible = borrow.zeroAllocEligible;
pub const Borrowed = borrow.Borrowed;
// serval-4e7
pub const Policy = options.Policy;
pub const DecodeOptions = options.DecodeOptions;
pub const EncodeOptions = options.EncodeOptions;
