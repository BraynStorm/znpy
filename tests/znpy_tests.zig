const std = @import("std");
const builtin = @import("builtin");

const T = std.testing;
test "znpy.simple" {
    const python = if (builtin.target.os.tag == .windows) "py" else "python";
    inline for (&[_][]const u8{"simple.py"}) |test_name| {
        const result = try std.process.Child.run(.{
            .allocator = std.testing.allocator,
            .argv = &[_][]const u8{ python, "test_" ++ test_name },
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
}
