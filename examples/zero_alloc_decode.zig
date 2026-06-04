// serval-15q
//! Allocation-model walkthrough: the three memory modes.
//! Borrowed decoding is not implemented yet — this demonstrates the API
//! shape with arena mode (free everything wholesale, no per-value frees).

const std = @import("std");
const serval = @import("serval");

const Event = struct {
    kind: []const u8,
    payload: []const u8,
};

pub fn main() !void {
    // arena mode: transient decode results, freed wholesale.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const event = try serval.json.decode(Event, arena.allocator(),
        \\{"kind":"ping","payload":"now"}
    , .{ .memory = .arena });

    std.debug.print("event: {s} ({s})\n", .{ event.kind, event.payload });

    // borrowed mode (future): result slices point into the input buffer;
    // valid only while the buffer is. See serval.codec.borrow.Borrowed.
    const mode: serval.codec.MemoryMode = .borrowed;
    std.debug.print("next up: MemoryMode.{s}\n", .{@tagName(mode)});
}
