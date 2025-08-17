const std = @import("std");
const znpy = @import("znpy");

comptime {
    znpy.defineExtensionModule();
}

pub fn take_some_array(kwargs: struct { array: znpy.numpy.array }) !f32 {
    const array = kwargs.array;
    return switch (array.shape().len) {
        1 => take_some_array_f32_1d(try .init(array)),
        2 => take_some_array_f32_2d(try .init(array)),
        3 => take_some_array_f32_3d(try .init(array)),
        else => return error.MaxDimsIs3,
    };
}
fn take_some_array_f32_1d(arr: znpy.numpy.array.typed(f32, 1)) f32 {
    var sum: f32 = 0;
    for (arr.slice1d(.{})) |e|
        sum += e;

    return sum;
}
fn take_some_array_f32_2d(arr: znpy.numpy.array.typed(f32, 2)) f32 {
    var sum: f32 = 0;
    for (0..arr.shape()[0]) |y| {
        for (arr.slice1d(.{y})) |e| {
            sum += e;
        }
    }

    return sum;
}
fn take_some_array_f32_3d(arr: znpy.numpy.array.typed(f32, 3)) f32 {
    const N = std.simd.suggestVectorLength(f32) orelse 4;
    const V = @Vector(N, f32);
    var sum_v: V = @splat(0);
    for (0..arr.shape()[0]) |z| {
        for (0..arr.shape()[1]) |y| {
            const elements = arr.slice1d(.{ z, y });
            const n_vectors = @divFloor(elements.len, @sizeOf(V));
            const vectorized_length = n_vectors * @sizeOf(V);
            const vectors: []align(1) const V = std.mem.bytesAsSlice(V, elements[0..vectorized_length]);
            for (vectors) |v| sum_v += v;
            for (elements[vectorized_length..]) |s| sum_v[0] += s;
        }
    }

    return @reduce(.Add, sum_v);
}
