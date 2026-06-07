// serval-9kw
//! serval-zon: ZON backend, bootstrapped on std.zon (config and metadata
//! are the driving use case). Bootstrap caveats vs serval-json:
//! - field names are Zig names (ZON keys are identifiers; rename metadata
//!   does not apply)
//! - shape failures (missing/unknown fields) surface as InvalidSyntax
//!   decode errors, not path-aware report issues
//! - no presence tracking (ctx.has() is always false)
//! - no borrowed mode (std.zon requires a sentinel-terminated copy)
//! - DecodeOptions.coercion is ignored (std.zon owns the parsing)
//! Constraint validation integrates exactly like serval-json.

pub const zon = @import("zon.zig");
// serval-xx5
pub const capabilities = zon.capabilities;
pub const decode = zon.decode;
pub const decodeResult = zon.decodeResult;
pub const encodeAlloc = zon.encodeAlloc;
// serval-x09
pub const decodeFromReader = zon.decodeFromReader;
pub const encodeToWriter = zon.encodeToWriter;
pub const measureEncodedLen = zon.measureEncodedLen;
pub const DecodeOptions = zon.DecodeOptions;
pub const EncodeOptions = zon.EncodeOptions;
