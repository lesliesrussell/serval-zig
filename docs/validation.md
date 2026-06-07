# Validation

## Rule taxonomy

- **Scalar**: `min`, `max`, `gt`, `lt` — applied to ints and floats (float
  bounds are integral-valued; use a custom validator for fractional
  limits); `one_of` — int membership (ints only)
- **String**: `min_len`, `max_len`, `pattern` + `pattern_full` (regex via
  [mvzr](https://github.com/mnemnion/mvzr), compiled at comptime — invalid
  patterns are compile errors; search semantics, anchor with `^...$` for
  full match), `email`, `url`, `one_of_str`, `nonempty`
- **Collection**: `min_items`, `max_items`, `unique`, `nonempty`
- **Cross-field**: `pub fn servalValidate(ctx, self)` hook on the struct
- **Transforms** (decode-time, before constraints): `trim` (allocation-free sub-slice), `lowercase` (allocates with the value allocator, even in borrowed mode). Typed check() and valueAgainstSchema see values as-is.

## Struct-level validators

Declare `pub fn servalValidate` on the type; `ctx.has(name)` reports whether
a field was present in the decoded input (always false outside the decode
pipeline):

```zig
pub fn servalValidate(ctx: *serval.core.ValidateContext, value: *const User) void {
    if (value.age != null and value.age.? < 18 and !ctx.has("guardian_email")) {
        ctx.issue(.{
            .path = .field("guardian_email"),
            .code = .required_when,
            .message = "guardian_email is required for minors",
        });
    }
}
```

## Reports

Every issue carries a `Path` (nested fields, array indices, map keys,
tagged union branches), an `IssueCode`, a message, and optional
expected/actual values. `report.ok()` is true iff there are no issues.

Paths are runtime-built and nested: `.addresses[1].zip` style, rendered
via `{f}` (`Path.format`). Issue paths are allocator-owned — free
reports with `report.deinit(allocator)` (or run everything in an
arena). Typed `check()` recurses into nested structs and
slice-of-struct elements, including their `servalValidate` hooks.

## Coercion modes

Set via `DecodeOptions.coercion` (JSON/MessagePack decode and buffered
union payloads) and `CheckOptions.coercion` (`valueAgainstSchema`); ZON
ignores it (std.zon owns the parsing). Typed `check()` ignores it too —
coercion is a decode-time concern.

- `none` — exact type matches only (default)
- `safe` — lossless: numeric string → int (exact parse), string → float,
  exact `"true"`/`"false"` → bool
- `aggressive` — adds lossy: float → int (truncated toward zero,
  out-of-range is `Overflow`), int 0/1 ↔ bool, scalar → string

Constraints always run against the coerced value.
