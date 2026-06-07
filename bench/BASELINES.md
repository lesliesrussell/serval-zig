# Benchmark Baselines

Machine: Apple Silicon (darwin 25.2.0), Zig 0.16.0 (homebrew), ReleaseFast.
Captured: 2026-06-07, commit at serval-wtv.

## Update protocol

Re-run `zig build bench` after perf-relevant changes (decoder/encoder
internals, the binary template, validation pipeline). Same machine
class only — these are guardrails against regressions in *this* repo's
history, not cross-machine claims. >15% regression on any row without
an explaining feature = investigate before merge. Update this file in
the same commit as the change that moves the numbers, with a one-line
justification.

## Numbers

```
json encode flat                         305 ns/op     415.6 MB/s  (127 bytes)
json decode flat owned                   410 ns/op     309.4 MB/s  (127 bytes)
json decode flat borrowed                375 ns/op     338.0 MB/s  (127 bytes)
json decode deep owned                  1713 ns/op     187.9 MB/s  (322 bytes)
json decode large full                157920 ns/op     302.8 MB/s  (47823 bytes)
json decode large projected              118 ns/op         (early exit; bytes not read)

msgpack encode flat                       84 ns/op    1136.2 MB/s  (96 bytes)
msgpack decode flat owned                 97 ns/op     985.3 MB/s  (96 bytes)
msgpack decode flat borrowed              77 ns/op    1239.9 MB/s  (96 bytes)
msgpack decode deep owned                560 ns/op     306.6 MB/s  (172 bytes)
msgpack decode large full              32172 ns/op    1325.7 MB/s  (42651 bytes)
msgpack decode large projected            40 ns/op         (early exit; bytes not read)

cbor encode flat                          71 ns/op    1362.5 MB/s  (98 bytes)
cbor decode flat owned                   130 ns/op     752.5 MB/s  (98 bytes)
cbor decode flat borrowed                120 ns/op     812.6 MB/s  (98 bytes)
cbor decode deep owned                   737 ns/op     233.2 MB/s  (172 bytes)
cbor decode large full                 42931 ns/op     995.9 MB/s  (42755 bytes)
cbor decode large projected               45 ns/op         (early exit; bytes not read)
```

## Reading notes

- Binary backends run 3–5× JSON throughput; CBOR encode edges msgpack
  (single-pass type-arg headers), msgpack decode edges CBOR.
- Borrowed beats owned by the string-dup cost, as designed.
- "large projected" demonstrates decodeProjection's top-level early
  exit: ~1,300× over full decode when projected fields lead the
  document. The MB/s figure is omitted there — the document tail is
  never read, so throughput-over-document-size is not meaningful.
