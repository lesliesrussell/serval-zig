// serval-15q
//! Decode result that separates syntax failure from semantic validation
//! failure.

const errors = @import("errors.zig");
// serval-ee8
const value_mod = @import("value.zig");

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
            // serval-ee8
            /// Top-level input fields not matching any schema field, when
            /// decoded with `.unknown_fields = .collect`. Value trees are
            /// allocator-built — decode with an arena and free wholesale.
            unknown: []const value_mod.FieldValue = &.{},
        };
    };
}
