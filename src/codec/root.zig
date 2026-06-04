// serval-15q
//! serval-codec: reader/writer-facing encode/decode interfaces and
//! allocation strategies. Isolates evolving std.Io specifics from the
//! rest of the codebase.

pub const codec = @import("codec.zig");
pub const decode = @import("decode.zig");
pub const encode = @import("encode.zig");
pub const reader = @import("reader.zig");
pub const writer = @import("writer.zig");
pub const options = @import("options.zig");
pub const borrow = @import("borrow.zig");
pub const alloc = @import("alloc.zig");

pub const MemoryMode = options.MemoryMode;
pub const DecodeOptions = options.DecodeOptions;
pub const EncodeOptions = options.EncodeOptions;
