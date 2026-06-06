# Serval

Serialization + validation for Zig. Serde/Pydantic-style: schema reflection,
multiple formats, rich path-aware validation, and explicit allocation modes
(borrowed / arena / owned).

**Status: v1 surface implemented** — JSON, ZON, and MessagePack backends,
full constraint engine, all four union tagging modes, streaming entry
points. CBOR and the dynamic `Value`-against-schema API are next.

## Usage

```zig
const serval = @import("serval");

const User = struct {
    id: u64,
    name: []const u8,
    email: []const u8,
    age: ?u8 = null,

    pub const serval = .{
        .rename_all = .camel_case,
        .fields = .{
            .name = .{ .min_len = 1, .max_len = 100 },
            .email = .{ .email = true },
            .age = .{ .min = 13, .max = 120 },
        },
    };
};

// Typed fast path — errors on syntax or validation failure.
const user = try serval.json.decode(User, allocator, input, .{});

// Full pipeline — path-aware reports instead of bare errors.
switch (try serval.json.decodeResult(User, allocator, input, .{})) {
    .ok => |ok| handle(ok.value), // ok.warnings under .lax validation
    .invalid => |report| for (report.issues) |i| log(i.path, i.code, i.message),
    .decode_error => |e| return e,
}

// Validation standalone, schema reflection, encode:
const report = try serval.validate.check(User, &user, allocator, .{});
const S = serval.schemaOf(User);
const json_out = try serval.json.encodeAlloc(User, allocator, user, .{ .pretty = true });
```

## Features

- **Schema metadata** via a `pub const serval = .{ ... }` declaration:
  `rename_all` (snake/camel/pascal/kebab), per-field constraints, bytes
  policy, enum/union tagging.
- **Validation**: scalar (`min`/`max`/`gt`/`lt`, ints and floats), string
  (`min_len`/`max_len`/`pattern` via regex/`email`/`url`), collection
  (`min_items`/`max_items`/`unique`), struct-level
  `pub fn servalValidate(ctx, self)` hooks with input-presence queries
  (`ctx.has`). Issues carry path, code, message, expected/actual.
- **Union tagging**: external, internal, adjacent (configurable tag/content
  keys), untagged.
- **Allocation modes**: `decodeBorrowed` returns input-borrowing results —
  zero heap allocations for escape-free flat input; arena and owned modes
  for everything else.
- **Streaming**: `decodeFromReader` / `encodeToWriter` /
  `measureEncodedLen` on every backend.
- **Lax mode**: return the value with constraint warnings attached instead
  of failing.

## Layout

| Module | Responsibility |
|---|---|
| `serval-core` | Schema model, field metadata, pathing, value representation, errors |
| `serval-validate` | Constraints, defaults, coercions, validation engine |
| `serval-codec` | Encode/decode interfaces, allocation strategies, `fromValue` dynamic mapper, IO boundary |
| `serval-json` | Schema-driven JSON backend |
| `serval-zon` | ZON backend (std.zon-based; config/metadata use cases) |
| `serval-msgpack` | MessagePack backend (wire format in-tree) |
| `serval` | Umbrella module re-exporting the above |

See `docs/architecture.md` for the design.

## Build

Requires Zig 0.16.0+. One dependency: [mvzr](https://github.com/mnemnion/mvzr)
(regex engine for `.pattern` rules), pinned in `build.zig.zon`.

```sh
zig build test      # run tests
zig build examples  # build examples into zig-out/bin
```
