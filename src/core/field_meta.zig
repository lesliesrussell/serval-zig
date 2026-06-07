// serval-15q
//! Per-field metadata attached via the `pub const serval = .{ .fields = ... }`
//! declaration on a type.

pub const FieldMeta = struct {
    rename: ?[]const u8 = null,
    required: bool = true,
    // Scalar rules
    min: ?i64 = null,
    max: ?i64 = null,
    gt: ?i64 = null,
    lt: ?i64 = null,
    // serval-elw: int membership (floats skip it — int list semantics)
    one_of: ?[]const i64 = null,
    // String rules
    min_len: ?usize = null,
    max_len: ?usize = null,
    pattern: ?[]const u8 = null,
    // serval-m9b: require the pattern to match the whole string instead
    // of mvzr's default search semantics.
    pattern_full: bool = false,
    email: bool = false,
    url: bool = false,
    // serval-elw
    one_of_str: ?[]const []const u8 = null,
    /// Strings and collections: len must be > 0.
    nonempty: bool = false,
    // Collection rules
    min_items: ?usize = null,
    max_items: ?usize = null,
    unique: bool = false,
    // serval-au2: string transforms, applied at decode time before
    // constraints run. trim is allocation-free (sub-slice); lowercase
    // allocates with the value allocator even in borrowed mode.
    trim: bool = false,
    lowercase: bool = false,
};
