// serval-15q
//! Coercion policy: how aggressively inputs are converted to target types.

pub const CoercionMode = enum {
    /// No conversions; types must match exactly.
    none,
    /// Lossless conversions only (e.g. int widening, "42" → 42 if enabled).
    safe,
    /// Lossy conversions allowed (e.g. float → int truncation).
    aggressive,
};
