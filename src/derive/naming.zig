// serval-15q
//! Field-name rename rules (rename_all policies).

const core = @import("serval-core");

/// Apply a rename rule to a field name at comptime.
/// Scaffold: identity for all rules; case conversion lands with the
/// metadata parser.
pub fn apply(comptime rule: core.attributes.RenameRule, comptime name: []const u8) []const u8 {
    return switch (rule) {
        .none => name,
        // TODO(serval): snake/camel/pascal/kebab conversion.
        else => name,
    };
}
