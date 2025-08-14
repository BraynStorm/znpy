const std = @import("std");
const znpy = @import("znpy");

pub const python_module = znpy.PythonModule{ .name = @import("options").znpy_module_name };

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
    const n_dims = array.ndarray.nd;
    std.debug.assert(n_dims == 2);

    const stride_0 = array.ndarray.strides[0];
    _ = stride_0; // autofix
    const stride_1 = array.ndarray.strides[1];
    _ = stride_1; // autofix
    const f32_data = @as(*f32, @ptrCast(@alignCast(array.ndarray.data)));

    return @intFromFloat(f32_data.*);
}
comptime {
    _ = znpy;
}
