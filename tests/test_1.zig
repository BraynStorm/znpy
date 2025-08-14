const std = @import("std");
const znpy = @import("znpy");

pub const python_module = znpy.PythonModule{ .name = @import("options").znpy_module_name };

fn debug(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn magic1(
    a: f32,
    b: f32,
    //
) f32 {
    return a + b;
}

pub fn take_some_array(
    array: znpy.numpy.array,
) u64 {
    const typed = array.withTypeAndDims(f32, 2);

    if (false) {
        _ = typed; // autofix
        const n_dims = array.ndarray.nd;
        std.debug.assert(n_dims == 2);

        const stride_0 = array.ndarray.strides[0];
        const stride_1 = array.ndarray.strides[1];
        debug("{}", .{ .strides = .{ stride_0, stride_1 } });

        const f32_data = @as(*f32, @ptrCast(@alignCast(array.ndarray.data)));

        return @intFromFloat(f32_data.*);
    } else {}
}
comptime {
    _ = znpy;
}
