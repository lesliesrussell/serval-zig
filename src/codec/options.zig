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

pub const EncodeOptions = struct {
    pretty: bool = false,
};
