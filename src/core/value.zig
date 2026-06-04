// serval-15q
//! Format-neutral intermediate value representation.
//! Fallback path for dynamic workflows and diagnostics — direct typed decode
//! is the fast path and never has to materialize a Value.

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    array: []const Value,
    object: []const FieldValue,
};

pub const FieldValue = struct {
    name: []const u8,
    value: Value,
};
