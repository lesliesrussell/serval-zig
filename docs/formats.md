# Formats

## Backend contract

Each format backend exposes:

- `decodeFromSlice` (alias of `decode`)
- `decodeFromReader` — streaming over `std.Io.Reader`
- `encodeToSlice` (alias of `encodeAlloc`)
- `encodeToWriter` — direct to `std.Io.Writer`
- `measureEncodedLen` — exact length without producing output

`serval.codec.codec.assertBackend(Backend)` comptime-checks conformance,
including a complete `capabilities` descriptor (`codec.Capabilities`) —
the status table below is machine-readable as flags consumers can
comptime-branch on.
std.Io specifics stay isolated in `src/codec/reader.zig` and
`src/codec/writer.zig`.

## Status

| Format | Status |
|---|---|
| JSON | Schema-driven both directions: wire names, bytes/enum policies, all four union tagging modes, presence tracking, borrowed mode |
| ZON | std.zon-based with full validation integration. Caveats: Zig field names only, shape failures fold into `InvalidSyntax`, no presence tracking, no borrowed mode |
| MessagePack | Wire format in-tree, schema-driven both directions: wire names, native str/bin via bytes_policy, all four union tagging modes, presence tracking, borrowed mode, streaming. Ext types unsupported |
| CBOR | Wire format in-tree (RFC 8949): same schema-driven feature set as MessagePack. Definite lengths only; tags rejected; f16 decoded, never emitted |

## Memory modes

- `borrowed` — result slices point into the input buffer; valid only while
  it is. `decodeBorrowed` makes the lifetime explicit via
  `codec.borrow.Borrowed(T)`. Escape-free flat input decodes with zero heap
  allocations (JSON only).
- `arena` — transient data into a caller-provided arena. Recommended for
  `.collect` mode and internal/untagged unions (buffered value trees become
  garbage after mapping).
- `owned` — fully owned result via allocator (default); string values are
  duplicated out of the input buffer.

## Union tagging

Declared on the union via `pub const serval = .{ .union_tagging = ... }`:

| Mode | Wire shape | Notes |
|---|---|---|
| `.external` (default) | `{"variant": payload}`; unit variants are bare strings | Streaming decode |
| `.adjacent` | `{"t": "variant", "c": payload}` | Keys via `union_tag_field`/`union_content_field`; tag must precede content; streaming decode |
| `.internal` | `{"kind": "variant", ...payload fields}` | Struct/void payloads only; tag position independent (buffered decode) |
| `.untagged` | payload bare | Variants tried in declaration order — order most→least specific; or set `untagged_policy = .unambiguous` to error (AmbiguousUnion) when >1 variant matches; buffered decode |
