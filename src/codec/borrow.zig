// serval-15q
//! Borrowed decoding support (MemoryMode.borrowed).
//! Lifetime rule: a Borrowed(T) is valid only as long as the input buffer
//! it was decoded from. This must stay painfully explicit in docs and
//! signatures.

const std = @import("std");
const core = @import("serval-core");

pub fn Borrowed(comptime T: type) type {
    return struct {
        /// Slices inside `value` may point into the input buffer.
        value: T,
        // serval-47j
        /// True when escapes or transforms forced heap allocations — the
        /// result then partially owns memory from the passed allocator.
        allocated: bool = false,
    };
}

// serval-47j
/// Comptime predicate: can this type's *shape* decode with zero heap
/// allocations in borrowed mode? True for scalars, enums, optionals,
/// strings, and nested structs of those — provided no `.lowercase`
/// transform is attached. Runtime conditions still apply: escape-free
/// input, `validation = .none`, and `unknown_fields != .collect`.
/// Non-u8 slices, arrays, and unions always allocate or buffer.
pub fn zeroAllocEligible(comptime T: type) bool {
    comptime {
        switch (@typeInfo(T)) {
            .bool, .int, .float, .@"enum" => return true,
            .optional => |o| return zeroAllocEligible(o.child),
            .pointer => |p| return p.size == .slice and p.child == u8,
            .@"struct" => {
                const S = core.schemaOf(T);
                const struct_fields = @typeInfo(T).@"struct".fields;
                for (S.fields, struct_fields) |sf, zf| {
                    if (sf.meta.lowercase) return false;
                    if (!zeroAllocEligible(zf.type)) return false;
                }
                return true;
            },
            else => return false,
        }
    }
}

// serval-47j
/// Allocator wrapper that counts allocations — used by decodeBorrowed to
/// report whether borrowing was pure or escapes forced allocation.
pub const CountingAllocator = struct {
    child: std.mem.Allocator,
    count: usize = 0,

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.count += 1;
        return self.child.vtable.alloc(self.child.ptr, len, alignment, ret_addr);
    }

    fn resizeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.child.vtable.resize(self.child.ptr, memory, alignment, new_len, ret_addr);
    }

    fn remapFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.child.vtable.remap(self.child.ptr, memory, alignment, new_len, ret_addr);
    }

    fn freeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.vtable.free(self.child.ptr, memory, alignment, ret_addr);
    }
};
