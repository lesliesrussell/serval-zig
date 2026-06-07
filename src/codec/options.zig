// serval-15q
//! Decode/encode options — the allocation model is a first-class design axis.

// serval-4tr
const validate = @import("serval-validate");
pub const CoercionMode = validate.CoercionMode;

pub const MemoryMode = enum {
    /// Returned data borrows from the input buffer where possible.
    /// Lifetime: result is valid only while the input buffer is.
    borrowed,
    /// Transient data allocated into a caller-provided arena.
    arena,
    /// Fully owned result via allocator.
    owned,
};

pub const DecodeOptions = struct {
    memory: MemoryMode = .owned,
    unknown_fields: enum { ignore, reject, collect } = .reject,
    // serval-4tr: shared enum so the mode flows into validate/fromValue.
    coercion: CoercionMode = .none,
    validation: enum { none, lax, strict } = .strict,
};

// serval-4e7
/// A shareable bundle of decode+encode knobs. Existing call sites are
/// unchanged — pass `policy.decode` / `policy.encode` where the split
/// options go today. Presets are starting points; copy and adjust.
pub const Policy = struct {
    decode: DecodeOptions = .{},
    encode: EncodeOptions = .{},

    /// The default surface: reject unknowns, no coercion, strict
    /// validation, owned memory.
    pub const strict: Policy = .{};

    /// Tolerant ingestion: ignore unknowns, safe coercion, lax validation
    /// (value returned with warnings attached).
    pub const lenient: Policy = .{
        .decode = .{
            .unknown_fields = .ignore,
            .coercion = .safe,
            .validation = .lax,
        },
    };

    /// Deterministic output for hashing/content-addressing; strict decode.
    pub const canonical_io: Policy = .{
        .encode = .{ .canonical = true },
    };
};

pub const EncodeOptions = struct {
    pretty: bool = false,
    // serval-sj2: deterministic output — map keys in canonical order per
    // wire format, minified. Floats stay fixed-width (documented
    // deviation from RFC 8949 §4.2.2 shortest-form).
    canonical: bool = false,
};
