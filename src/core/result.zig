// serval-15q
//! Decode result that separates syntax failure from semantic validation
//! failure.

const errors = @import("errors.zig");

pub fn DecodeResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        invalid: errors.ValidationReport,
        decode_error: errors.DecodeError,
    };
}
