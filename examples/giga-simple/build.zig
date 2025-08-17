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
    const znpy_mod, const install_pyd = try znpy.znpyImbue(
        b,
        b.dependency("znpy", .{}),
        my_fun_pyd,
        target,
        optimize,
        false,
    );
    my_fun_pyd.root_module.addImport("znpy", znpy_mod);

    // TODO: add utils in znpy to smooth this DX.
    b.getInstallStep().dependOn(&install_pyd.step);
    b.getInstallStep().dependOn(&b.addInstallArtifact(my_fun_pyd, .{
        .dest_dir = .{ .override = .bin },
        .dest_sub_path = if (target.result.os.tag == .windows) "exty.pyd" else "exty.so",
    }).step);
}
