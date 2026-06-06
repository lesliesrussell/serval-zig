// serval-15q
//! Format-backend contract. Each backend (json, zon, msgpack) provides the
//! broad, minimal entry points: decodeFromSlice, decodeFromReader,
//! encodeToWriter, encodeToSlice, and measureEncodedLen where possible.
//! Backends conform by convention (comptime duck typing), checked here.

const options = @import("options.zig");

/// Comptime check that a backend type exposes the expected entry points.
pub fn assertBackend(comptime Backend: type) void {
    if (!@hasDecl(Backend, "decodeFromSlice"))
        @compileError(@typeName(Backend) ++ " missing decodeFromSlice");
    if (!@hasDecl(Backend, "encodeToSlice"))
        @compileError(@typeName(Backend) ++ " missing encodeToSlice");
    // serval-x09
    if (!@hasDecl(Backend, "decodeFromReader"))
        @compileError(@typeName(Backend) ++ " missing decodeFromReader");
    if (!@hasDecl(Backend, "encodeToWriter"))
        @compileError(@typeName(Backend) ++ " missing encodeToWriter");
    if (!@hasDecl(Backend, "measureEncodedLen"))
        @compileError(@typeName(Backend) ++ " missing measureEncodedLen");
}

pub const DecodeOptions = options.DecodeOptions;
pub const EncodeOptions = options.EncodeOptions;
