// serval-15q
//! Format-backend contract. Each backend (json, zon, msgpack) provides the
//! broad, minimal entry points: decodeFromSlice, decodeFromReader,
//! encodeToWriter, encodeToSlice, and measureEncodedLen where possible.
//! Backends conform by convention (comptime duck typing), checked here.

const options = @import("options.zig");

// serval-sj2
const std = @import("std");

/// Canonical map-key ordering per wire format.
pub const KeyOrder = enum {
    /// Byte-lexicographic over key content (JSON — note: not full JCS,
    /// which sorts UTF-16 code units; msgpack).
    lexicographic,
    /// Shorter keys first, then bytes — RFC 8949 §4.2.1 bytewise order of
    /// the encoded form, for definite-length text keys (CBOR).
    length_first,
};

// serval-sj2
pub fn keyLess(comptime order: KeyOrder, a: []const u8, b: []const u8) bool {
    switch (order) {
        .lexicographic => return std.mem.lessThan(u8, a, b),
        .length_first => {
            if (a.len != b.len) return a.len < b.len;
            return std.mem.lessThan(u8, a, b);
        },
    }
}

// serval-sj2
/// Comptime index permutation putting `names` in canonical order.
pub fn sortedKeyIndices(comptime names: []const []const u8, comptime order: KeyOrder) [names.len]usize {
    comptime {
        var idx: [names.len]usize = undefined;
        for (0..names.len) |i| idx[i] = i;
        var i: usize = 1;
        while (i < names.len) : (i += 1) {
            var j = i;
            while (j > 0 and keyLess(order, names[idx[j]], names[idx[j - 1]])) : (j -= 1) {
                const t = idx[j];
                idx[j] = idx[j - 1];
                idx[j - 1] = t;
            }
        }
        return idx;
    }
}

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
