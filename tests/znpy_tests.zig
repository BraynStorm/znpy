const std = @import("std");
const builtin = @import("builtin");
const T = std.testing;

const python = if (builtin.target.os.tag == .windows) "py" else "python";
fn py_test(test_name: []const u8) !void {
    var env_map = try std.process.getEnvMap(std.testing.allocator);
    defer env_map.deinit();

    const path_sep = if (builtin.target.os.tag == .windows) ';' else ':';
    if (env_map.get("PYTHONPATH")) |old_pp| {
        const python_path = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}{c}{s}",
            .{ old_pp, path_sep, "zig-out/tests" },
        );
        defer std.testing.allocator.free(python_path);
        env_map.remove("PYTHONPATH");
        try env_map.put("PYTHONPATH", python_path);
    }

    const result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ python, test_name },
        .cwd = "zig-out/tests",
        .env_map = &env_map,
        .progress_node = std.Progress.Node{
            .index = .none,
        },
    });

    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    var buffer: [64]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &stderr_writer.interface;
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
    try stderr.flush();

    try std.testing.expectEqualStrings("Exited", @tagName(result.term));
    try std.testing.expectEqual(result.term.Exited, 0);
}

test "znpy.simple" {
    try py_test("test_simple.py");
}
test "znpy.numpy" {
    try py_test("test_numpy.py");
}
