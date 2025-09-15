const std = @import("std");

const c = @import("c.zig").c;
const List = @import("List.zig");
const numpy = @import("numpy.zig");
const options = @import("znpy_options");
const znpy = @import("znpy.zig");

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
            switch (T) {
                List => {
                    if (check(c.PyList_Check, .{py_value})) {
                        return .{ .py_object = @ptrCast(py_value) };
                    }
                    return error.NotImplemented_Unknown;
                },
                znpy.Dict => {
                    if (check(c.PyDict_Check, .{py_value})) {
                        return .{ .py_object = @ptrCast(py_value) };
                    }
                    return error.NotImplemented_Unknown;
                },
                else => if (T == numpy.array) {
                    if (std.meta.eql(
                        @as(usize, @intFromPtr(@as([*c]?*c.PyTypeObject, @ptrCast(c.PyArray_API))[2])),
                        @as(usize, @intFromPtr(py_value.?.ob_type)),
                    )) {
                        return numpy.array{ .ndarray = @as(*c.PyArrayObject, @ptrCast(py_value)) };
                    } else {
                        return error.TypeMismatch;
                    }
                },
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
                    //- bs: view to str, bytes, bytearray or memoryview
                    if (pyTypeMatch(py_value, &c.PyUnicode_Type)) {
                        return try pyBytesSlice(znpy.String, pp.is_const, py_value);
                    } else if (pyTypeMatch(py_value, &c.PyBytes_Type)) {
                        return try pyBytesSlice(c.PyBytesObject, pp.is_const, py_value);
                    } else if (pyTypeMatch(py_value, &c.PyByteArray_Type)) {
                        return try pyBytesSlice(c.PyByteArrayObject, pp.is_const, py_value);
                    } else if (pyTypeMatch(py_value, &c.PyMemoryView_Type)) {
                        return try pyBytesSlice(c.PyMemoryViewObject, pp.is_const, py_value);
                    }
                    return null;
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
    const ResultT = @TypeOf(result);
    return switch (@typeInfo(ResultT)) {
        .int => |int_t| switch (int_t.signedness) {
            .signed => c.PyLong_FromLongLong(@intCast(result)),
            .unsigned => c.PyLong_FromUnsignedLongLong(@intCast(result)),
        },
        .float => c.PyFloat_FromDouble(result),
        .optional => if (result) |real_result| valueToPyObject(real_result) else c.Py_None(),
        .void => c.Py_None(),
        .@"struct" => switch (ResultT) {
            znpy.String => result.py_object,
            else => {
                @compileLog("Unsupported return type (yet!)", result);
                @compileError("");
            },
        },
        else => {
            @compileLog("Unsupported return type (yet!)", result);
            @compileError("");
        },
    };
}

fn pyTypeMatch(object: [*c]c.PyObject, typeobject: [*c]c.PyTypeObject) bool {
    return object.*.ob_type == typeobject or
        c.PyType_IsSubtype(object.*.ob_type, typeobject) != 0;
}

fn canUseMacros() bool {
    return options.python_version.major >= 3 and
        options.python_version.minor >= 11;
}

extern fn PyUnicode_AsUTF8AndSize(unicode: [*c]c.PyObject, size: [*c]c.Py_ssize_t) callconv(.c) [*c]const u8;

fn pyBytesSlice(
    comptime T: type,
    comptime is_const: bool,
    py_object: [*c]c.PyObject,
) !(if (is_const) []const u8 else []u8) {
    const can_use_macros = comptime canUseMacros();

    switch (T) {
        znpy.String => {
            if (!is_const)
                return error.TypeMismatch;

            // if (can_use_macros) {
            var size: isize = undefined;
            var data: [*c]const u8 = PyUnicode_AsUTF8AndSize(py_object, &size);
            return data[0..@intCast(size)];
            // }
        },
        c.PyBytesObject => {
            if (!is_const)
                return error.TypeMismatch;

            const py_bytes: [*c]c.PyBytesObject = @ptrCast(py_object);
            const data: [*c]const u8 = if (can_use_macros) c.PyBytes_AS_STRING(py_object) else &py_bytes.*.ob_sval;
            const size: isize = if (can_use_macros) c.PyBytes_GET_SIZE(py_object) else py_bytes.*.ob_base.ob_size;

            return data[0..@intCast(size)];
        },
        c.PyMemoryViewObject => {
            // TODO:
            //  Add conversion to bytes if the object supports
            //  the buffer protocol (memoryview, etc)
            return error.NotImplemented_MemoryView;
        },
        c.PyByteArrayObject => {
            const py_byte_array: [*c]c.PyByteArrayObject = @ptrCast(py_object);
            const data: [*c]u8 = if (can_use_macros) c.PyByteArray_AS_STRING(py_object) else py_byte_array.*.ob_start;
            const size: isize = if (can_use_macros) c.PyByteArray_GET_SIZE(py_object) else py_byte_array.*.ob_base.ob_size;
            return data[0..@intCast(size)];
        },
        else => unreachable,
    }
}
