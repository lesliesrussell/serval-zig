# Serval

Serialization + validation for Zig. Serde/Pydantic-style: schema reflection,
multiple formats, rich path-aware validation, and explicit allocation modes
(borrowed / arena / owned).

**Status: scaffold.** API shape is in place; the validation engine and
schema-driven codecs are under construction.

## Usage

```zig
const serval = @import("serval");

const User = struct {
    id: u64,
    name: []const u8,
    age: ?u8 = null,

    pub const serval = .{
        .fields = .{
            .name = .{ .min_len = 1, .max_len = 100 },
            .age = .{ .min = 13, .max = 120 },
        },
    };
};

const schema = serval.schemaOf(User);
const user = try serval.json.decode(User, allocator, input, .{});
const report = try serval.validate.check(User, &user, allocator, .{});
```

## Layout

| Module | Responsibility |
|---|---|
| `serval-core` | Schema model, field metadata, pathing, value representation, errors |
| `serval-validate` | Constraints, defaults, coercions, validation engine |
| `serval-codec` | Encode/decode interfaces, allocation strategies, IO boundary |
| `serval-json` | JSON backend (ZON, msgpack later) |
| `serval` | Umbrella module re-exporting the above |

See `docs/architecture.md` for the full design.

## Build

Requires Zig 0.16.0+.

```sh
zig build test      # run tests
zig build examples  # build examples into zig-out/bin
```
