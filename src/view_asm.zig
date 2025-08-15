const std = @import("std");
const builtin = @import("builtin");

// TODO: bad but good
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const leak_alloc = arena.allocator();

pub fn main() !void {
    const args = try std.process.argsAlloc(leak_alloc);

    _ = args; // autofix
}
