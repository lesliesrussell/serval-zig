# Architecture

This page is the working architecture summary; frozen semantics live in
[SPEC.md](SPEC.md).

## Principle

**Stable semantic center, unstable backends at the edge.** The long-term
asset is the schema + validation model. Formats and IO integrations are
replaceable adapters.

## Modules

- `serval-core` — schema model (`Schema(T)`), field metadata, pathing,
  format-neutral `Value`, error types (`ValidationReport`, `DecodeError`).
  No wire-format dependencies. Highest stability.
- `serval-validate` — constraint taxonomy, coercion policy, defaults,
  validation engine. Depends on core only.
- `serval-codec` — decode/encode interfaces, the three memory modes
  (borrowed/arena/owned), and the std.Io boundary (isolated in
  `reader.zig`/`writer.zig` because Zig IO is still evolving).
- `serval-json` (+ future `serval-zon`, `serval-msgpack`) — format
  backends conforming to the codec contract.
- `serval` — umbrella module; `@import("serval")` exposes `serval.core`,
  `serval.validate`, `serval.codec`, `serval.json` as re-exports.

## Core types

- `Schema(T)` — comptime-generated structural metadata: fields, wire names,
  optional/default markers, constraints, tagging policies.
- `Value` — small format-neutral union. Fallback path for dynamic
  workflows/diagnostics; typed decode is the fast path.
- `ValidationReport` — list of `ValidationIssue` (path, code, message,
  expected/actual). Never a bare `error.Invalid`.
- `DecodeResult(T)` — `ok | invalid | decode_error`; syntax failure and
  semantic validation failure are different problem classes.

## Metadata model

Zig has no attributes, so customization is an explicit declaration adjacent
to the type:

```zig
pub const serval = .{
    .rename_all = .snake_case,
    .fields = .{
        .name = .{ .min_len = 1, .max_len = 100 },
        .email = .{ .email = true },
    },
};
```

## Validation pipeline

1. **Shape** — required fields, unknown fields, type mismatches, union tags.
2. **Coercion/defaulting** — policy-gated conversions, fill defaults.
3. **Constraints** — ranges, lengths, patterns, membership, cross-field
   hooks.

## Milestones

- v1: core schema inspection; scalar/string/collection rules with
  path-aware reporting; JSON backend; borrowed vs owned decode; docs.
- v1.1: ZON backend; enum tagging and bytes-policy options.
- Later: MessagePack, CBOR; CSV/YAML if demand proves real.
