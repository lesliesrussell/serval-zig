// serval-15q
//! Decode result that separates syntax failure from semantic validation
//! failure.

const errors = @import("errors.zig");

pub fn DecodeResult(comptime T: type) type {
    return union(enum) {
        ok: Ok,
        invalid: errors.ValidationReport,
        decode_error: errors.DecodeError,

        // serval-w98
        /// With lax validation, constraint failures land here as warnings
        /// instead of making the result .invalid. Caller frees
        /// `warnings.issues` (empty unless lax produced any).
        pub const Ok = struct {
            value: T,
            warnings: errors.ValidationReport = .{},
        };
    };
}
