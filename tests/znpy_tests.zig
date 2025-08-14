const std = @import("std");

const T = std.testing;
test "znpy.simple" {
    const result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "python", "test_1.py" },
        .cwd = "zig-out/tests",
        .progress_node = std.Progress.Node{
            .index = .none,
        },
    });

    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    const stderr = std.io.getStdErr().writer();
    if (result.stdout.len > 0) {
        try stderr.print("--------------------------------\n", .{});
        try stderr.print("{s}", .{result.stdout});
    }

    if (result.stderr.len > 0) {
        if (result.stdout.len == 0) {
            try stderr.print("--------------------------------\n", .{});
        }
        try stderr.print("{s}", .{result.stderr});
    }
    if (result.stdout.len > 0 or result.stderr.len > 0) {
        try stderr.print("--------------------------------\n", .{});
    }

    try std.testing.expectEqualStrings("Exited", @tagName(result.term));
    try std.testing.expectEqual(result.term.Exited, 0);
}
