const std = @import("std");

fn createTests(
    b: *std.Build,
    znpy: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) *std.Build.Step.Run {
    const unittest_pyd = b.addSharedLibrary(.{
        .name = "znpy_test_simple",
        .root_source_file = b.path("tests/test_simple.zig"),
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

    // emit raw ASM
    b.getInstallStep().dependOn(&b.addInstallFile(
        unittest_pyd.getEmittedAsm(),
        std.fmt.allocPrint(b.allocator, "{s}-{s}-raw.s", .{
            unittest_pyd.name,
            @tagName(optimize),
        }) catch unreachable,
    ).step);

    // emit clean ASM (rust)
    // const asm_cleaner = b.addExecutable(.{
    //     .name = "asm_cleaner",
    //     .root_source_file = b.path("tools/asm_cleaner.zig"),
    //     .single_threaded = true,
    //     .optimize = .ReleaseFast,
    //     .strip = true,
    //     .target = target,
    // });

    // const clean_asm_zig = b.addRunArtifact(asm_cleaner);
    // clean_asm_zig.setStdIn(.{ .lazy_path = unittest_pyd.getEmittedAsm() });
    // b.getInstallStep().dependOn(&b.addInstallFile(
    //     clean_asm_zig.captureStdOut(),
    //     std.fmt.allocPrint(b.allocator, "{s}-{s}-clean-zig.s", .{
    //         unittest_pyd.name,
    //         @tagName(optimize),
    //     }) catch unreachable,
    // ).step);

    // test
    const unittest_test = b.addTest(.{
        .root_source_file = b.path("tests/znpy_tests.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const unittest_run = b.addRunArtifact(unittest_test);
    unittest_run.step.dependOn(&install_test_pyd.step); // require the PYD to be installed

    const copy_test_py = b.addInstallFileWithDir(
        b.path("tests/test_simple.py"),
        tests_install_dir,
        "test_simple.py",
    );

    const unittest_cmd = b.step("test", "Test ZNPY");
    unittest_cmd.dependOn(b.getInstallStep());
    unittest_cmd.dependOn(&unittest_run.step);
    unittest_cmd.dependOn(&copy_test_py.step);

    return unittest_run;
}

fn readCommandOutput(b: *std.Build, command: []const []const u8) ?[]const u8 {
    const child = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = command,
    }) catch @panic("failed to run command");
    if (child.term.Exited != 0) return null;

    // NOTE(bozho2): leak stdout/stderr buffers.
    return std.mem.trimRight(u8, child.stdout, "\n\r\t ");
}

const PythonVersion = struct {
    major: u16,
    minor: u16,
    // patch: u16,
};

/// str = "Python 3.13.5"
fn parsePythonVersion(str: []const u8) !PythonVersion {
    const prefix = "Python ";
    std.debug.print("-> {s}\n", .{str});
    if (!(std.mem.startsWith(u8, str, prefix))) return error.PythonWTF;
    var iter = std.mem.tokenizeScalar(u8, str[prefix.len..], '.');
    return .{
        .major = try std.fmt.parseInt(u8, iter.next() orelse "", 10), // empty string as default
        .minor = try std.fmt.parseInt(u8, iter.next() orelse "", 10), // on purpose
        // .patch = try std.fmt.parseInt(u8, iter.next() orelse "", 10), // so we can fail if it's not there
    };
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

    const znpy_options = b.addOptions();
    znpy.addOptions("znpy_options", znpy_options);

    //- bs: decide what launcher to use
    const python_exe = if (target.result.os.tag == .windows) "py" else "python";

    //- bs: find python version
    const python_version_str = readCommandOutput(b, &[_][]const u8{ python_exe, "--version" }).?;
    const python_version = try parsePythonVersion(python_version_str);
    znpy_options.addOption(PythonVersion, "python_version", python_version);

    //- bs: find python include path
    const python_include_path = readCommandOutput(b, &[_][]const u8{ python_exe, "-c", "from sysconfig import get_paths; print(get_paths()['include'])" }).?;
    znpy.addSystemIncludePath(.{ .cwd_relative = python_include_path });

    //- bs: find numpy include path, if available
    var numpy_available = false;
    if (readCommandOutput(b, &[_][]const u8{ python_exe, "-c", "import numpy as np; print(np.get_include())" })) |numpy_include_path| {
        znpy.addSystemIncludePath(.{ .cwd_relative = numpy_include_path });
        numpy_available = true;
    }
    znpy_options.addOption(bool, "numpy_available", numpy_available);

    //- bs: link the necessary lib file on Windows
    if (target.result.os.tag == .windows) {
        znpy.addLibraryPath(.{ .cwd_relative = readCommandOutput(b, &[_][]const u8{ "py", "-c", "from sysconfig import get_paths; print(get_paths()['data'] + '/libs')" }).? });
        const python_library = try std.fmt.allocPrint(b.allocator, "python{d}{d}", .{
            python_version.major,
            python_version.minor,
        });
        znpy.linkSystemLibrary(python_library, .{});
    }

    //- bs: add some tests
    _ = createTests(b, znpy, target, optimize, strip);

    // const run_cmd = b.addRunArtifact(lib);
    // run_cmd.step.dependOn(lib_install);
    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

}
