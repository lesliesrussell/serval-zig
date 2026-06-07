# Serval Semantics Specification

This document freezes the semantics that backends and features must agree
on. Every normative statement here is pinned by a test in
`tests/spec_test.zig` (or referenced suite); changing one is a deliberate
spec revision, not a refactor. Sections marked **DECISION** are open calls
recorded in §10.

## 1. Scope and stability

`serval-core`'s semantic model — `Schema(T)`, `Value`, `ValidationReport`,
`DecodeResult(T)` — is the stability anchor. Format backends are adapters
and MUST NOT introduce semantics not expressible in this document.
API-level conformance is enforced by `codec.codec.assertBackend`; semantic
conformance by the cross-backend conformance suite (serval-9a3).

## 2. The Value contract

`Value` is a **lowest-common-denominator data model with explicit loss
points**, not a lossless IR:

- `int: i64` — integers outside i64 (`u64 > maxInt(i64)`) **error with
  `Overflow` on any dynamic path** (`decodeValue`, `.collect`, buffered
  unions). The typed path is lossless for all `u64`. *(DECISION D1: widen
  to i128.)*
- `float: f64` — f16/f32 wire values widen losslessly; no fixed-point.
- `string` vs `bytes` — distinct variants. Text-only formats (JSON, ZON)
  never produce `.bytes`; binary formats produce `.bytes` for their byte
  string types. `fromValue` accepts either for `[]const u8` targets.
- `null` is a distinct variant; absence of a key is NOT a `Value` — it is
  presence information (§6).
- Object key order preserves input order; duplicate keys are not detected
  (last-write-wins through typed decode; both retained in raw `Value`).

## 3. Numeric semantics

- Typed integer decode is exact: any wire integer that fits the target
  type round-trips; out-of-range is `error.Overflow`, never wraparound.
- Typed float decode: wire f16/f32/f64 widen or `@floatCast` to the
  target; integers convert via `@floatFromInt` in every mode (this is
  representation flexibility, not coercion — JSON `2` and `2.0` are the
  same number).
- Backends MUST select minimal-width encodings but accept any width on
  decode (pinned by int-width roundtrip tests in each backend suite).

## 4. Coercion matrix

Coercion is **decode-time** (and `valueAgainstSchema`-time) only. Typed
`check()` never coerces (§8). Modes: `.none` (default) ⊂ `.safe` ⊂
`.aggressive`.

| Wire → target | none | safe | aggressive |
|---|---|---|---|
| numeric string → int | ✗ | exact base-10 parse | same as safe |
| numeric string → float | ✗ | `parseFloat` | same as safe |
| `"true"`/`"false"` → bool | ✗ | ✓ (exact) | ✓ |
| float/sci-notation number → int | ✗ | ✗ | trunc toward zero |
| int 0/1 → bool | ✗ | ✗ | ✓ (only 0/1; `2` errors) |
| bool → int | ✗ | ✗ | 0/1 |
| scalar → string | ✗ | ✗ | token text / formatted |

Edge semantics (all pinned):

- String→int parsing accepts an optional leading sign; rejects any
  whitespace; rejects scientific notation **in every mode** (string
  coercion is exact-int only — deliberately asymmetric with number
  tokens, which reach ints via aggressive truncation).
- *(DECISION D3)* `std.fmt.parseInt` accepts Zig digit separators:
  `"1_0"` currently coerces to `10`.
- *(DECISION D2)* `parseFloat` accepts `inf`/`nan` spellings: string
  `"inf"` currently coerces into float fields under `.safe`.
- Float→int truncates toward zero; out-of-range **and non-finite** map to
  `error.Overflow` *(DECISION D4)*.
- ZON ignores coercion entirely (std.zon owns parsing) — a documented
  capability gap, to become a flag under serval-xx5.

## 5. Equality

Wherever serval compares values (`.unique`, future canonical checks):

- Current implementation is `std.meta.eql` — **field-wise for structs,
  `==` for scalars, pointer identity for slices**. The slice behavior is
  a known defect for `.unique` (serval-m9b replaces it with deep
  equality: strings/bytes by content).
- Float equality is `==`: `NaN ≠ NaN` (a NaN never counts as a
  duplicate), `-0.0 == 0.0` (they do). This is frozen unless D-future
  revisits bitwise comparison.
- `.unique` on the dynamic path stays unimplemented until the deep-eql
  definition lands.

## 6. Presence

`ctx.has(name)` means **the field's key appeared in the decoded input**,
under the Zig field name, at the top level of the decoded type:

- Defaulted and optional-filled fields are absent (pinned).
- Presence is populated only by decode pipelines and only when
  `validation != .none` (so the zero-allocation guarantee holds);
  standalone `check()` and ZON decode always report absent.
- Presence is *input* presence — coercion/transforms don't affect it.
  Missing-vs-null is therefore expressible: `?T` field, `has()` false +
  null = omitted; `has()` true + null = explicit null.

## 7. Allocation guarantees

| Mode | Guarantee |
|---|---|
| `.owned` | Every string/bytes duplicated; result independent of input buffer. |
| `.arena` | Result data allocated with the caller's allocator; strings may reference the input buffer. Free wholesale. |
| `.borrowed` | Strings/bytes reference the input buffer wherever bytes are verbatim. **Zero heap allocations** for flat structs (no non-u8 slices, no unions, no collected unknowns) with escape-free input and `validation = .none` — pinned with `failing_allocator` in json/msgpack/cbor suites. |

Caveats that break zero-alloc (all documented at their features): escaped
JSON strings, `.lowercase` transform (always allocates), non-u8 slices,
buffered unions, `.collect`, presence tracking (hence the
`validation != .none` gate), streaming readers. `.trim` is sub-slice and
allocation-free. Issue paths are allocator-owned — reports are freed via
`ValidationReport.deinit` and only exist when issues were raised.

## 8. Pipeline phase model

Logical phases: **parse → coerce → transform → default → shape-check →
constrain → report**. Concretely:

- Coercion happens *during* parse, at the token/value boundary (§4).
- Transforms run per-field immediately after that field decodes,
  **before** any constraint sees the value (pinned: `trim` + `min_len`).
- Defaults fill after the container closes; missing required fields are
  shape issues (`.required`), not decode errors, surfacing in
  `DecodeResult.invalid`.
- Constraint validation runs last over the fully built value, with
  presence data attached.

Entry-point matrix:

| Entry point | parse | coerce | transform | default | shape | constrain |
|---|---|---|---|---|---|---|
| `decode`/`decodeResult` | ✓ | ✓ | ✓ | ✓ | ✓ | per `validation` |
| `decode` w/ `.validation = .none` (**parse-only mode**) | ✓ | ✓ | ✓ | ✓ | required/unknown only | ✗ |
| typed `check()` | — | ✗ | ✗ | — | — | ✓ (+ hooks, nested) |
| `valueAgainstSchema` | — | per `CheckOptions.coercion` (view-only) | ✗ | — | ✓ | ✓ |

Two consequences worth naming: **parse-only decoding already exists**
(`.validation = .none`); **fail-with-full-report already exists**
(`decodeResult` → `.invalid`). `check()` seeing untransformed values is
the documented asymmetry (pinned) — a normalize-then-check variant is
future work, not a v1 promise.

## 9. Backend semantic equivalence

For any value expressible in two backends' capability sets, decode∘encode
MUST produce identical typed results, and invalid inputs MUST produce the
same `IssueCode`/`DecodeError` classification. Enforced by serval-9a3.
Known capability gaps (ZON: no presence/borrowed/coercion, folded shape
errors; CBOR: no tags/indefinite; msgpack: no ext) are declared gaps, not
permitted divergences.

## 10. Open decisions

| ID | Question | Current behavior | Options |
|---|---|---|---|
| D1 | `Value.int` width | i64; big u64 → `Overflow` on dynamic paths | keep i64 / widen to i128 |
| D2 | `"inf"`/`"nan"` strings into floats under `.safe` | accepted (parseFloat) | keep / restrict to finite decimal |
| D3 | Zig digit separators in string→int coercion | `"1_0"` → 10 | keep / reject `_` |
| D4 | Non-finite float→int error code | `Overflow` | keep / distinct `UnexpectedToken` |

Resolutions are recorded here and their pinning tests updated in the same
commit.
