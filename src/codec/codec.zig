// serval-15q
//! Format-backend contract. Each backend (json, zon, msgpack) provides the
//! broad, minimal entry points: decodeFromSlice, decodeFromReader,
//! encodeToWriter, encodeToSlice, and measureEncodedLen where possible.
//! Backends conform by convention (comptime duck typing), checked here.

const options = @import("options.zig");

// serval-xx5
/// How a backend supports one union tagging mode.
pub const UnionModeSupport = enum {
    /// Decoded directly from the token/cursor stream.
    streaming,
    /// Decoded by buffering a Value tree first (arena recommended).
    buffered,
    /// Serval tagging metadata is not honored by this backend.
    unsupported,
};

// serval-xx5
/// Machine-readable capability descriptor every backend must declare.
/// Documentation gaps become flags consumers can comptime-branch on.
pub const Capabilities = struct {
    /// ctx.has() reflects input presence during decode validation.
    presence_tracking: bool,
    /// MemoryMode.borrowed honored (input-referencing results).
    borrowed_mode: bool,
    /// DecodeOptions.coercion honored.
    coercion: bool,
    /// rename_all / .rename metadata applied to wire names.
    rename_metadata: bool,
    /// Shape failures surface as path-aware report issues rather than
    /// folding into decode errors.
    shape_issue_fidelity: bool,
    /// unknown_fields = .collect gathers into DecodeResult.Ok.unknown.
    collect_unknown: bool,
    union_external: UnionModeSupport,
    union_adjacent: UnionModeSupport,
    union_internal: UnionModeSupport,
    union_untagged: UnionModeSupport,
};

/// Comptime check that a backend type exposes the expected entry points
/// and a complete capability descriptor.
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
    // serval-xx5
    if (!@hasDecl(Backend, "capabilities"))
        @compileError(@typeName(Backend) ++ " missing capabilities descriptor");
    if (@TypeOf(Backend.capabilities) != Capabilities)
        @compileError(@typeName(Backend) ++ ".capabilities must be a codec Capabilities value");
}

pub const DecodeOptions = options.DecodeOptions;
pub const EncodeOptions = options.EncodeOptions;
