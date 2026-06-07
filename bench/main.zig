// serval-wtv
//! Microbenchmarks. Run via `zig build bench` — the build wires a
//! dedicated ReleaseFast module graph regardless of -Doptimize, so
//! numbers are honest by default. Compare against bench/BASELINES.md.

const std = @import("std");
const serval = @import("serval");

// --- Fixtures -------------------------------------------------------------

const Flat = struct {
    id: u64 = 123456789,
    name: []const u8 = "ada lovelace",
    email: []const u8 = "ada@example.com",
    age: ?u8 = 36,
    score: f64 = 99.5,
    active: bool = true,
    kind: enum { admin, member, guest } = .member,
    count: u32 = 42,
};

const L5 = struct { x: u64 = 5, s: []const u8 = "leaf" };
const L4 = struct { x: u64 = 4, s: []const u8 = "l4", n: L5 = .{} };
const L3 = struct { x: u64 = 3, s: []const u8 = "l3", n: L4 = .{} };
const L2 = struct { x: u64 = 2, s: []const u8 = "l2", n: L3 = .{} };
const L1 = struct { x: u64 = 1, s: []const u8 = "l1", n: L2 = .{} };
const Deep = struct { a: L1 = .{}, b: L1 = .{}, c: L1 = .{} };

const Item = struct { id: u64, name: []const u8, val: f64 };
const Large = struct { head_id: u64, head_kind: []const u8, items: []const Item };
const Head = struct { head_id: u64, head_kind: []const u8 };

const backends = .{ serval.json, serval.msgpack, serval.cbor };
const backend_names = .{ "json", "msgpack", "cbor" };

// --- Harness ---------------------------------------------------------------

fn nowNs() u64 {
    // 0.16 moved clocks behind the Io interface; libc is fine for a bench.
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

fn report(comptime label: []const u8, iters: usize, total_ns: u64, bytes_per_op: usize) void {
    const ns_per_op = total_ns / iters;
    const mb_s = if (total_ns == 0) 0 else (@as(f64, @floatFromInt(bytes_per_op * iters)) * 1e9) /
        (@as(f64, @floatFromInt(total_ns)) * 1e6);
    std.debug.print("{s:<34} {d:>9} ns/op {d:>9.1} MB/s  ({d} bytes, {d} iters)\n", .{ label, ns_per_op, mb_s, bytes_per_op, iters });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // long-lived fixture memory
    var keep = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer keep.deinit();
    const k = keep.allocator();

    std.debug.print("serval bench (ReleaseFast)\n\n", .{});

    const flat = Flat{};
    const deep = Deep{};

    var items: [1000]Item = undefined;
    for (&items, 0..) |*it, i| {
        it.* = .{ .id = i, .name = "item-name-payload", .val = @floatFromInt(i) };
    }
    const large = Large{ .head_id = 7, .head_kind = "event", .items = &items };

    inline for (backends, backend_names) |B, name| {
        const flat_doc = try B.encodeAlloc(Flat, k, flat, .{});
        const deep_doc = try B.encodeAlloc(Deep, k, deep, .{});
        const large_doc = try B.encodeAlloc(Large, k, large, .{});

        {
            const iters = 200_000;
            const t0 = nowNs();
            for (0..iters) |_| {
                _ = arena.reset(.retain_capacity);
                const out = B.encodeAlloc(Flat, a, flat, .{}) catch unreachable;
                std.mem.doNotOptimizeAway(out.ptr);
            }
            report(name ++ " encode flat", iters, nowNs() - t0, flat_doc.len);
        }
        {
            const iters = 200_000;
            const t0 = nowNs();
            for (0..iters) |_| {
                _ = arena.reset(.retain_capacity);
                const v = B.decode(Flat, a, flat_doc, .{}) catch unreachable;
                std.mem.doNotOptimizeAway(&v);
            }
            report(name ++ " decode flat owned", iters, nowNs() - t0, flat_doc.len);
        }
        {
            const iters = 200_000;
            const t0 = nowNs();
            for (0..iters) |_| {
                _ = arena.reset(.retain_capacity);
                const v = B.decodeBorrowed(Flat, a, flat_doc, .{ .validation = .none }) catch unreachable;
                std.mem.doNotOptimizeAway(&v.value);
            }
            report(name ++ " decode flat borrowed", iters, nowNs() - t0, flat_doc.len);
        }
        {
            const iters = 50_000;
            const t0 = nowNs();
            for (0..iters) |_| {
                _ = arena.reset(.retain_capacity);
                const v = B.decode(Deep, a, deep_doc, .{}) catch unreachable;
                std.mem.doNotOptimizeAway(&v);
            }
            report(name ++ " decode deep owned", iters, nowNs() - t0, deep_doc.len);
        }
        {
            const iters = 2_000;
            const t0 = nowNs();
            for (0..iters) |_| {
                _ = arena.reset(.retain_capacity);
                const v = B.decode(Large, a, large_doc, .{}) catch unreachable;
                std.mem.doNotOptimizeAway(&v);
            }
            report(name ++ " decode large full", iters, nowNs() - t0, large_doc.len);
        }
        {
            const iters = 200_000;
            const t0 = nowNs();
            for (0..iters) |_| {
                _ = arena.reset(.retain_capacity);
                const v = B.decodeProjection(Head, a, large_doc, .{}) catch unreachable;
                std.mem.doNotOptimizeAway(&v);
            }
            report(name ++ " decode large projected", iters, nowNs() - t0, large_doc.len);
        }
        std.debug.print("\n", .{});
    }
}
