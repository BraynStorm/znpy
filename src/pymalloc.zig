//! Wrapper around
//! - PyMem_Malloc
//! - PyMem_Realloc
//! - PyMem_Free

const std = @import("std");
const c = @import("c.zig").c;

const PyAlloc = @This();

fn rawAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = ret_addr;

    // TODO: handle alignment
    _ = alignment; // autofix
    const ptr = c.PyMem_Malloc(len);

    //- bs: case A - out of memory
    return if (ptr) |mem| @ptrCast(mem) else null;
}

fn rawFree(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = ctx;
    _ = ret_addr;

    // TODO: handle alignment
    _ = alignment; // autofix
    c.PyMem_Free(memory.ptr);
}
fn rawRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    _ = ctx;
    _ = alignment;
    _ = ret_addr;
    return if (c.PyMem_Realloc(memory.ptr, new_len)) |ptr|
        @ptrCast(ptr)
    else
        null;
}

pub fn allocator() std.mem.Allocator {
    return std.mem.Allocator{
        .ptr = undefined,
        .vtable = &std.mem.Allocator.VTable{
            .alloc = &rawAlloc,
            .resize = &std.mem.Allocator.noResize,
            .remap = &rawRemap,
            .free = &rawFree,
        },
    };
}
