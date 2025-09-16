//! Allow passing callbacks to extension functions

const std = @import("std");

const c = @import("c.zig").c;
const znpy = @import("znpy.zig");

const Function = @This();

py_object: *c.PyObject,

pub fn call_v1(
    self: Function,
    args: anytype,
    kwargs: anytype,
) ?*c.PyObject {
    _ = kwargs; // autofix
    // 1. Convert args to python tuple.
    const ArgsT = @TypeOf(args);
    const ArgsInfo = @typeInfo(ArgsT).@"struct";

    const py_args = c.PyTuple_New(@intCast(ArgsInfo.fields.len)) orelse return null;
    defer c.Py_DecRef(py_args);

    inline for (ArgsInfo.fields, 0..) |field, i| {
        const arg = @field(args, field.name);
        const py_arg = znpy.convert.valueToPyObject(if (field.type == comptime_int)
            @as(isize, arg)
        else
            arg);
        errdefer c.Py_DecRef(py_arg);

        const result = c.PyTuple_SetItem(py_args, i, py_arg);
        std.debug.assert(result == 0);
    }

    const py_kwargs = c.PyDict_New() orelse return null;
    defer c.Py_DecRef(py_kwargs);

    return c.PyObject_Call(self.py_object, py_args, py_kwargs);
}
