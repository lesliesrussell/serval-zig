# Formats

## Backend contract

Each format backend exposes the broad, minimal entry points:

- `decodeFromSlice`
- `decodeFromReader` (planned)
- `encodeToSlice`
- `encodeToWriter` (planned)
- `measureEncodedLen` (where possible)

`serval.codec.codec.assertBackend(Backend)` comptime-checks conformance.
std.Io specifics stay isolated in `src/codec/reader.zig` and
`src/codec/writer.zig`.

## Status

| Format | Status |
|---|---|
| JSON | Scaffolded on std.json; schema-driven decoder planned |
| ZON | Placeholder (v1.1) |
| MessagePack | Placeholder (post-v1.1) |
| CBOR | Planned (post-v1.1) |

## Memory modes

- `borrowed` — results borrow from the input buffer (planned; lifetime
  rules will be explicit in signatures via `codec.borrow.Borrowed(T)`)
- `arena` — transient data into a caller-provided arena
- `owned` — fully owned result via allocator (default)
