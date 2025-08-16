const std = @import("std");

fn startsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.startsWith(u8, haystack, needle);
}
fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}
pub fn main() !void {
    const stdin = std.io.getStdIn();
    const reader = stdin.reader();
    const stdout = std.io.getStdOut();
    try stdout.lock(.exclusive);
    const writer = stdout.writer();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    while (try reader.readUntilDelimiterOrEofAlloc(alloc, '\n', std.math.maxInt(usize))) |line| : (_ = arena.reset(.retain_capacity)) {
        if (startsWith(line, ".LFE")) {
            try writer.writeByte('\n');
            continue;
        }

        if (startsWith(line, "0:") or
            startsWith(line, ".Lframe1"))
        {
            //- bs: stop reading after this.
            break;
        }

        if ((!startsWith(line, "\t.") or
            (startsWith(line, "\t.quad") or
                startsWith(line, "\t.string") or
                startsWith(line, "\t.ascii") or
                startsWith(line, "\t.asciz")))
        //
        and
            !(startsWith(line, ".LF") or
                startsWith(line, ".Lfunc") or
                startsWith(line, ".LCFI") or
                startsWith(line, ".LEH") or
                startsWith(line, ".LHOT") or
                startsWith(line, ".LCOLD") or
                startsWith(line, ".LLSDA") or
                contains(line, "endbr64")))
        {
            try writer.writeAll(line);
            try writer.writeByte('\n');
        }
    }
}
