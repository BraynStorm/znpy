//! Wrapper around
//! - PyMem_Malloc
//! - PyMem_Realloc
//! - PyMem_Free

const std = @import("std");
const c = @import("c.zig").c;

const PyAlloc = @This();

fn rawAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = ctx; // autofix
    _ = alignment; // autofix
    _ = ret_addr; // autofix

    // TODO: handle alignment
    const ptr = c.PyMem_Malloc(len);

    //- bs: case A - out of memory
    return if (ptr) |mem| @ptrCast(mem) else null;
}

fn rawFree(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = ctx; // autofix
    _ = alignment; // autofix
    _ = ret_addr; // autofix
    // TODO: handle alignment
    c.PyMem_Free(memory.ptr);
}

// fn rawResize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
//     _ = ctx; // autofix
//     _ = memory; // autofix
//     _ = alignment; // autofix
//     _ = new_len; // autofix
//     _ = ret_addr; // autofix
// }

fn rawRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    _ = ctx; // autofix
    _ = alignment; // autofix
    _ = ret_addr; // autofix
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
