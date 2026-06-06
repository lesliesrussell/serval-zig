# Validation

## Rule taxonomy

- **Scalar**: `min`, `max`, `gt`, `lt` — applied to ints and floats (float
  bounds are integral-valued; use a custom validator for fractional limits)
- **String**: `min_len`, `max_len`, `pattern` (regex via
  [mvzr](https://github.com/mnemnion/mvzr), compiled at comptime — invalid
  patterns are compile errors; search semantics, anchor with `^...$` for
  full match), `email`, `url`
- **Collection**: `min_items`, `max_items`, `unique`
- **Cross-field**: `pub fn servalValidate(ctx, self)` hook on the struct
- Planned: `one_of`, `nonempty`, transform/coercion rules (`trim`,
  `lowercase`, policy-gated numeric/string coercion)

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

## Coercion modes

- `none` — exact type matches only (default)
- `safe` — lossless conversions
- `aggressive` — lossy conversions allowed
