// serval-4am
//! Comptime field-name case conversion for rename_all policies.
//! Source names are assumed to follow Zig's snake_case convention.

const std = @import("std");
const attributes = @import("attributes.zig");

pub fn convert(comptime rule: attributes.RenameRule, comptime name: []const u8) []const u8 {
    const result = comptime blk: {
        switch (rule) {
            .none, .snake_case => break :blk name,
            .kebab_case => {
                var buf: [name.len]u8 = undefined;
                for (name, 0..) |c, i| buf[i] = if (c == '_') '-' else c;
                const final = buf;
                break :blk &final;
            },
            .camel_case, .pascal_case => {
                var buf: [name.len]u8 = undefined;
                var n: usize = 0;
                var upper_next = rule == .pascal_case;
                for (name) |c| {
                    if (c == '_') {
                        upper_next = true;
                        continue;
                    }
                    buf[n] = if (upper_next) std.ascii.toUpper(c) else c;
                    upper_next = false;
                    n += 1;
                }
                const final = buf[0..n].*;
                break :blk &final;
            },
        }
    };
    return result;
}
