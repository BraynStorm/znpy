const std = @import("std");
const znpy = @import("znpy");

pub const python_module = znpy.PythonModule{ .name = @import("options").znpy_module_name };
comptime {
    _ = znpy;
}

fn debug(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn divide_f32(
    args: struct {
        a: f32,
        b: f32,
    },
) f32 {
    return args.a / args.b;
}

pub fn divide_f32_default_1(
    args: struct {
        a: f32,
        b: f32 = 1,
    },
) f32 {
    return args.a / args.b;
}
