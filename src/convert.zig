const std = @import("std");

const c = @import("c.zig").c;
const List = @import("List.zig");
const numpy = @import("numpy.zig");

pub const ParseValueError = error{
    TypeMismatch,
    ConversionFailed,
    NotImplemented_Unknown,
    NotImplemented_Struct,
    NotImplemented_MemoryView,
};

/// run a PyXX_Check(args) in a return-type-agnostic way.
inline fn check(callable: anytype, args: anytype) bool {
    const r = @call(.auto, callable, args);
    return switch (@typeInfo(@TypeOf(r))) {
        .int => r != 0,
        .bool => r,
        else => unreachable,
    };
}
/// Converts a Python value to a normal Zig data type.
///
/// - null - the user passed a Python None
/// - error - exception must be raised to the Python code, probably a TypeError
pub fn pyObjectToValue(comptime T: type, py_value: ?*c.PyObject) ParseValueError!?T {
    switch (@typeInfo(T)) {
        .optional => |opt| {
            return if (c.Py_IsNone(py_value) != 0)
                pyObjectToValue(opt.child, py_value)
            else
                null;
        },
        .int => |int_t| {
            if (!check(c.PyNumber_Check, .{py_value}))
                return error.TypeMismatch;

            const number = if (int_t.signedness == .signed)
                c.PyLong_AsLongLong(py_value)
            else
                c.PyLong_AsUnsignedLongLong(py_value);
            return @intCast(number);
        },
        .float => {
            if (!check(c.PyNumber_Check, .{py_value}))
                return error.TypeMismatch;

            return @floatCast(c.PyFloat_AsDouble(py_value));
        },
        .bool => {
            return switch (c.PyObject_IsTrue(py_value)) {
                0 => false,
                1 => true,
                else => error.ConversionFailed,
            };
        },
        .@"struct" => {
            if (T == List) {
                if (check(c.PyList_Check, .{py_value})) {
                    return .{ .object = @ptrCast(py_value) };
                }
                return error.NotImplemented_Unknown;
            } else if (T == numpy.array) {
                if (std.meta.eql(
                    @as(usize, @intFromPtr(@as([*c]?*c.PyTypeObject, @ptrCast(c.PyArray_API))[2])),
                    @as(usize, @intFromPtr(py_value.?.ob_type)),
                )) {
                    return numpy.array{ .ndarray = @as(*c.PyArrayObject, @ptrCast(py_value)) };
                } else {
                    return error.TypeMismatch;
                }
            }
            return error.NotImplemented_Struct;
        },
        .pointer => |pp| {
            std.debug.assert(pp.address_space == .generic);
            std.debug.assert(pp.alignment == 1);
            std.debug.assert(pp.is_allowzero == false);
            std.debug.assert(pp.is_volatile == false);

            switch (pp.size) {
                .slice => {
                    if (pp.is_const) {
                        //- bs: view to bytes, bytearray or memoryview
                        if (check(c.PyBytes_Check, .{py_value})) {
                            const data: [*c]const u8 = c.PyBytes_AS_STRING(py_value);
                            const data_len: isize = c.PyBytes_GET_SIZE(py_value);
                            return data[0..@intCast(data_len)];
                        } else if (check(c.PyByteArray_Check, .{py_value})) {
                            const data: [*c]const u8 = c.PyByteArray_AS_STRING(py_value);
                            const data_len: isize = c.PyByteArray_GET_SIZE(py_value);
                            return data[0..@intCast(data_len)];
                        } else if (check(c.PyMemoryView_Check, .{py_value})) {
                            // TODO:
                            //  Add conversion to bytes if the object supports
                            //  the buffer protocol (memoryview, etc)
                            return error.NotImplemented_MemoryView;
                        }
                        return null;
                    } else {
                        //- bs: pointer to bytearray
                        if (check(c.PyByteArray_Check, .{py_value})) {
                            const data: [*c]u8 = c.PyByteArray_AS_STRING(py_value);
                            const data_len: isize = c.PyByteArray_GET_SIZE(py_value);
                            return data[0..@intCast(data_len)];
                        } else if (check(c.PyMemoryView_Check, .{py_value})) {
                            // TODO: Implement.
                            return error.NotImplemented_MemoryView;
                        }
                        return error.TypeMismatch;
                    }
                },
                else => {
                    @compileLog(T);
                    @compileError("Only slices are supported");
                },
            }
        },
        else => return error.NotImplemented_Unknown,
    }
}

pub fn valueToPyObject(result: anytype) *c.PyObject {
    const result_t = @TypeOf(result);
    return switch (@typeInfo(result_t)) {
        .int => |int_t| switch (int_t.signedness) {
            .signed => c.PyLong_FromLongLong(@intCast(result)),
            .unsigned => c.PyLong_FromUnsignedLongLong(@intCast(result)),
        },
        .float => c.PyFloat_FromDouble(result),
        .optional => if (result) |real_result| valueToPyObject(real_result) else c.Py_None(),
        .void => c.Py_None(),
        else => {
            @compileLog("Unsupported return type (yet!)", result);
            @compileError("");
        },
    };
}
