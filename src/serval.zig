// serval-15q
//! Serval — serialization + validation for Zig.
//!
//! Umbrella module: most users `@import("serval")` and reach everything via
//! `serval.core`, `serval.validate`, `serval.json`. Advanced users can wire
//! the underlying modules (serval-core, serval-validate, serval-codec,
//! serval-json) directly in their build.zig.

pub const core = @import("serval-core");
pub const validate = @import("serval-validate");
pub const codec = @import("serval-codec");
pub const json = @import("serval-json");
// serval-9kw
pub const zon = @import("serval-zon");
// serval-bfi
pub const msgpack = @import("serval-msgpack");
// serval-7jg
pub const cbor = @import("serval-cbor");

pub const derive = @import("derive/derive.zig");
// serval-9ov
pub const schema_export = @import("export/json_schema.zig");

pub const testing = struct {
    pub const fixtures = @import("testing/fixtures.zig");
    pub const roundtrip = @import("testing/roundtrip.zig");
    pub const fuzz = @import("testing/fuzz.zig");
};

// Convenience re-exports for the common path.
pub const schemaOf = core.schemaOf;
pub const Schema = core.Schema;
pub const Value = core.Value;
pub const ValidationReport = core.ValidationReport;
pub const DecodeResult = core.DecodeResult;
