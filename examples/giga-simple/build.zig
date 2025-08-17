const std = @import("std");

const znpy = @import("znpy");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const my_fun_pyd = b.addSharedLibrary(.{
        .name = "exty",
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });
    const znpy_mod, const install_pyd = try znpy.newZNPY(
        b,
        my_fun_pyd,
        target,
        optimize,
        false,
    );
    my_fun_pyd.root_module.addImport("znpy", znpy_mod);

    b.getInstallStep().dependOn(&install_pyd.step);
}
