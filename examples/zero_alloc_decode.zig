// serval-0mq
//! Allocation-model walkthrough: borrowed vs arena decode.

const std = @import("std");
const serval = @import("serval");

const Event = struct {
    kind: []const u8,
    payload: []const u8,
};

pub fn main() !void {
    const input =
        \\{"kind":"ping","payload":"now"}
    ;

    // borrowed mode: result slices point into the input buffer — valid only
    // while it is. Escape-free flat input decodes with ZERO allocations
    // (proven here with the failing allocator).
    const borrowed = try serval.json.decodeBorrowed(
        Event,
        std.testing.failing_allocator,
        input,
        .{ .validation = .none },
    );
    std.debug.print("borrowed (0 allocs): {s} ({s})\n", .{ borrowed.value.kind, borrowed.value.payload });

    // arena mode: transient decode results, freed wholesale.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const owned = try serval.json.decode(Event, arena.allocator(), input, .{ .memory = .arena });
    std.debug.print("arena: {s} ({s})\n", .{ owned.kind, owned.payload });
}
