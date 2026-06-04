// serval-15q
//! Default-filling for missing fields during the coercion/defaulting phase.

/// Reserved: fill missing fields from struct field defaults and
/// `pub const serval` metadata. Implemented with the decode pipeline.
pub fn applyDefaults(comptime T: type, value: *T) void {
    _ = value;
}
