const std = @import("std");

fn createTests(
    b: *std.Build,
    znpy: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) *std.Build.Step.Run {
    const unittest_pyd = b.addSharedLibrary(.{
        .name = "znpy_test",
        .root_source_file = b.path("tests/test_1.zig"),
        .optimize = optimize,
        .target = target,
        .single_threaded = true,
        .strip = strip,
    });
    unittest_pyd.root_module.addImport("znpy", znpy);

    const opt = b.addOptions();
    opt.addOption([:0]const u8, "znpy_module_name", b.allocator.dupeZ(u8, unittest_pyd.name) catch unreachable);
    unittest_pyd.root_module.addImport("options", opt.createModule());

    const tests_install_dir: std.Build.InstallDir = .{ .custom = "tests" };

    const install_test_pyd = b.addInstallArtifact(
        unittest_pyd,
        .{ .dest_dir = .{ .override = tests_install_dir } },
    );
    if (target.result.os.tag == .windows) {
        install_test_pyd.dest_sub_path = std.fmt.allocPrint(
            b.allocator,
            "{s}.pyd",
            .{unittest_pyd.name},
        ) catch unreachable;
    } else {
        install_test_pyd.dest_sub_path = std.fmt.allocPrint(
            b.allocator,
            "{s}.so",
            .{unittest_pyd.name},
        ) catch unreachable;
    }

    const unittest_test = b.addTest(.{
        .root_source_file = b.path("tests/znpy_tests.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const unittest_step = b.addRunArtifact(unittest_test);
    unittest_step.step.dependOn(&install_test_pyd.step); // require the PYD to be installed

    const copy_test_py = b.addInstallFileWithDir(
        b.path("tests/test_1.py"),
        tests_install_dir,
        "test_1.py",
    );

    const unittest_cmd = b.step("test", "Test ZNPY");
    unittest_cmd.dependOn(&unittest_step.step);
    unittest_cmd.dependOn(&copy_test_py.step);

    return unittest_step;
}

fn readCommandOutput(b: *std.Build, command: []const []const u8) ![]const u8 {
    const child = try std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = command,
    });
    // NOTE(bozho2): leak stdout/stderr buffers.
    return std.mem.trimRight(u8, child.stdout, "\n\r\t ");
}
pub fn build(
    b: *std.Build,
) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "strip binary") orelse false;

    const znpy = b.addModule("znpy", .{
        .root_source_file = b.path("src/znpy.zig"),
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        znpy.addSystemIncludePath(.{ .cwd_relative = try readCommandOutput(b, &[_][]const u8{ "py", "-3.7", "-c", "from sysconfig import get_paths; print(get_paths()['include'])" }) });
        znpy.addSystemIncludePath(.{ .cwd_relative = try readCommandOutput(b, &[_][]const u8{ "python", "-c", "import numpy as np; print(np.get_include())" }) });
        znpy.addLibraryPath(.{ .cwd_relative = try readCommandOutput(b, &[_][]const u8{ "py", "-3.7", "-c", "from sysconfig import get_paths; print(get_paths()['data'] + '/libs')" }) });
        znpy.linkSystemLibrary("python37", .{});
    } else {
        znpy.addSystemIncludePath(.{ .cwd_relative = "/usr/include/python3.13" }); // TODO: allow specifying as a build option.
        znpy.addSystemIncludePath(.{ .cwd_relative = "/usr/lib/python3.13/site-packages/numpy/_core/include" }); // TODO: allow specifying as a build option.
    }
    _ = createTests(b, znpy, target, optimize, strip);

    // const run_cmd = b.addRunArtifact(lib);
    // run_cmd.step.dependOn(lib_install);
    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

}
