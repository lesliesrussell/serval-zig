// serval-15q
//! serval-validate: constraints, defaults, coercions, validation engine.
//! Three-phase pipeline: shape → coercion/defaulting → constraints.

pub const validate = @import("validate.zig");
pub const rules = @import("rules.zig");
pub const constraint = @import("constraint.zig");
pub const coercion = @import("coercion.zig");
pub const defaults = @import("defaults.zig");
pub const path = @import("path.zig");

pub const check = validate.check;
pub const CheckOptions = validate.CheckOptions;
pub const CoercionMode = coercion.CoercionMode;
pub const Constraint = constraint.Constraint;
