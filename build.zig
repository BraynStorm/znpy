const std = @import("std");

pub fn znpyImbue(
    b: *std.Build,
    znpy_dep: *std.Build.Dependency,
    shared_library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) !struct {
    *std.Build.Module,
    *std.Build.Step.InstallFile,
} {
    return newZNPY_impl(
        b,
        shared_library,
        target,
        optimize,
        strip,
        znpy_dep.path("src/znpy.zig"),
        znpy_dep.path("src/pyi.zig"),
    );
}

fn newZNPY(
    b: *std.Build,
    shared_library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) !struct {
    *std.Build.Module,
    *std.Build.Step.InstallFile,
} {
    return newZNPY_impl(
        b,
        shared_library,
        target,
        optimize,
        strip,
        b.path("src/znpy.zig"),
        b.path("src/pyi.zig"),
    );
}
fn newZNPY_impl(
    b: *std.Build,
    shared_library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    znpy_zig_path: std.Build.LazyPath,
    pyi_zig_path: std.Build.LazyPath,
) !struct {
    *std.Build.Module,
    *std.Build.Step.InstallFile,
} {
    //- bs: sanity check
    std.debug.assert(shared_library.isDynamicLibrary());

    const name = try b.allocator.dupeZ(u8, shared_library.name);

    const znpy = b.addModule("znpy", .{
        .root_source_file = znpy_zig_path,
        .link_libc = true,
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    znpy.addImport("extension_lib", shared_library.root_module);
    const znpy_options = b.addOptions();
    znpy.addOptions("znpy_options", znpy_options);
    znpy_options.addOption([:0]const u8, "pyd_name", name);

    znpy.addIncludePath(b.path("src"));

    //- bs: decide what launcher to use
    const python_exe = if (target.result.os.tag == .windows) "py" else "python";

    //- bs: find python version
    const python_version_str = readCommandOutput(b, &[_][]const u8{ python_exe, "--version" }).?;
    const python_version = try parsePythonVersion(python_version_str);
    znpy_options.addOption(PythonVersion, "python_version", python_version);
    if (target.result.os.tag == .windows) {
        znpy.linkSystemLibrary(b.fmt("python{d}{d}", .{ python_version.major, python_version.minor }), .{ .needed = true });
    } else {
        if (python_version.major == 3 and python_version.minor <= 7) {
            znpy.linkSystemLibrary(b.fmt("python{d}.{d}m", .{ python_version.major, python_version.minor }), .{ .needed = true });
        } else {
            znpy.linkSystemLibrary(b.fmt("python{d}.{d}", .{ python_version.major, python_version.minor }), .{ .needed = true });
        }
    }

    //- bs: find python include path
    const python_include_path = readCommandOutput(b, &[_][]const u8{ python_exe, "-c", "from sysconfig import get_paths; print(get_paths()['include'])" }).?;
    znpy.addSystemIncludePath(.{ .cwd_relative = python_include_path });

    //- bs: find numpy include path, if available
    var numpy_version: ?std.SemanticVersion = null;
    if (readCommandOutput(b, &[_][]const u8{ python_exe, "-c", "import numpy as np; print(np.get_include())" })) |numpy_include_path| {
        znpy.addSystemIncludePath(.{ .cwd_relative = numpy_include_path });
        znpy.addCMacro("ZNPY_NUMPY_AVAILABLE", "1");
        if (readCommandOutput(b, &[_][]const u8{ python_exe, "-c", "import numpy as np; print(np.__version__)" })) |numpy_version_str| {
            numpy_version = try parseNumpyVersion(numpy_version_str);
            znpy_options.addOption(NumpyVersion, "numpy_version", numpy_version.?);
        } else {
            unreachable;
        }
    }
    znpy_options.addOption(bool, "numpy_available", numpy_version != null);

    //- bs: link the necessary lib file on Windows
    if (target.result.os.tag == .windows) {
        znpy.addLibraryPath(.{ .cwd_relative = readCommandOutput(b, &[_][]const u8{
            "py",
            b.fmt("-{d}.{d}", .{ python_version.major, python_version.minor }),
            "-c",
            "import sysconfig; print(sysconfig.get_paths()['data'] + '\\libs')",
        }).? });
        const python_library_minor = b.fmt("python{d}{d}", .{ python_version.major, python_version.minor });
        znpy.linkSystemLibrary(python_library_minor, .{});

        if (numpy_version != null) {
            znpy.addLibraryPath(.{ .cwd_relative = readCommandOutput(b, &[_][]const u8{ python_exe, "-c", "import numpy as np; print(np.get_include().replace('\\include', '\\lib'))" }).? });
            znpy.linkSystemLibrary("npymath", .{});
        }
    }

    const pyi_name = b.fmt("{s}.pyi", .{name});
    const gen_pyi_exe = b.addExecutable(.{
        .name = b.fmt("gen-pyi-{s}", .{name}),
        .root_module = b.createModule(.{
            .root_source_file = pyi_zig_path,
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }),
    });
    gen_pyi_exe.root_module.addImport("znpy", znpy);
    gen_pyi_exe.root_module.addImport("extension_lib", shared_library.root_module);
    const gen_pyi = b.addRunArtifact(gen_pyi_exe);
    return .{
        znpy,
        b.addInstallFileWithDir(gen_pyi.captureStdOut(), .bin, pyi_name),
    };
}

fn createTest(
    b: *std.Build,
    name: [:0]const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    install_dir: std.Build.InstallDir,
) !*std.Build.Step {
    const alloc = b.allocator;

    const zig_filename = b.fmt("{s}.zig", .{name});
    const py_filename = b.fmt("{s}.py", .{name});

    const pyd = b.addLibrary(.{
        .name = name,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = try b.path("tests").join(alloc, zig_filename),
            .optimize = optimize,
            .target = target,
            .single_threaded = true,
            .strip = strip,
        }),
    });

    const znpy, const install_pyi_file = try newZNPY(b, pyd, target, optimize, strip);
    install_pyi_file.dir = install_dir;
    pyd.root_module.addImport("znpy", znpy);

    const install_pyd = b.addInstallArtifact(pyd, .{ .dest_dir = .{ .override = install_dir } });
    install_pyd.step.dependOn(&install_pyi_file.step);

    if (target.result.os.tag == .windows) {
        install_pyd.dest_sub_path = b.fmt("{s}.pyd", .{name});
    } else {
        install_pyd.dest_sub_path = b.fmt("{s}.so", .{name});
    }

    const install_py = b.addInstallFileWithDir(try b.path("tests").join(alloc, py_filename), install_dir, py_filename);
    install_py.step.dependOn(&install_pyd.step);
    return &install_py.step;
}
fn createTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) !void {
    const tests_install_dir: std.Build.InstallDir = .{ .custom = "tests" };

    // emit raw ASM
    // b.getInstallStep().dependOn(&b.addInstallFile(
    //     unittest_pyd.getEmittedAsm(),
    //     std.fmt.allocPrint(b.allocator, "{s}-{s}-raw.s", .{
    //         unittest_pyd.name,
    //         @tagName(optimize),
    //     }) catch unreachable,
    // ).step);

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
    const harness = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/znpy_tests.zig"),
            .single_threaded = true,
            .target = target,
            .optimize = optimize,
        }),
    });

    const test_simple_install = try createTest(b, "test_simple", target, optimize, strip, tests_install_dir);
    const test_numpy_install = try createTest(b, "test_numpy", target, optimize, strip, tests_install_dir);
    const test_callbacks_install = try createTest(b, "test_callbacks", target, optimize, strip, tests_install_dir);

    const harness_run = b.addRunArtifact(harness);
    harness_run.step.dependOn(test_simple_install);
    harness_run.step.dependOn(test_numpy_install);
    harness_run.step.dependOn(test_callbacks_install);

    const harness_cmd = b.step("test", "Test ZNPY");
    harness_cmd.dependOn(&harness_run.step);
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

const PythonVersion = std.SemanticVersion;
const NumpyVersion = std.SemanticVersion;

/// str = "Python 3.13.5"
fn parsePythonVersion(str: []const u8) !PythonVersion {
    const prefix = "Python ";
    if (!(std.mem.startsWith(u8, str, prefix))) return error.PythonWTF;
    return try std.SemanticVersion.parse(str[prefix.len..]);
}

fn parseNumpyVersion(str: []const u8) !NumpyVersion {
    return try std.SemanticVersion.parse(str);
}

pub fn build(
    b: *std.Build,
) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "strip binary") orelse false;
    try createTests(b, target, optimize, strip);
}
