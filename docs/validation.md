# Validation

## Rule taxonomy (v1)

- **Scalar**: `min`, `max`, `gt`, `lt`, `one_of`
- **String**: `min_len`, `max_len`, `pattern` (regex via [mvzr](https://github.com/mnemnion/mvzr); search semantics — anchor with `^...$` for full match), `email`, `url`
- **Collection**: `min_items`, `max_items`, `unique`
- **Presence**: `required`, `nonempty`
- **Cross-field**: custom function hooks at the struct level
- **Transform/coercion**: `trim`, `lowercase`, numeric/string coercion
  (only when explicitly enabled)

## Struct-level validators

```zig
pub fn validateUser(ctx: *serval.core.ValidateContext, value: *const User) void {
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
