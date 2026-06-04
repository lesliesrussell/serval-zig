// serval-15q
//! A single applicable constraint, tagged by rule family.

const rules = @import("rules.zig");

pub const Constraint = union(enum) {
    scalar: rules.Scalar,
    string: rules.String,
    collection: rules.Collection,
    presence: rules.Presence,
};
