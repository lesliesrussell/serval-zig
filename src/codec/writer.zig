// serval-15q
//! Single point of contact with std.Io.Writer. Format backends consume this
//! alias so std.Io churn stays contained here.

const std = @import("std");

pub const Writer = std.Io.Writer;
