const std = @import("std");
const c = @import("c.zig").c;
const convert = @import("convert.zig");

const List = @This();

py_object: *c.PyObject,

pub const Iter = struct {
    iter: *c.PyObject,

    pub fn init(list: List) !Iter {
        const maybe_iter: ?*c.PyObject = c.PyObject_GetIter(list.py_object);
        return if (maybe_iter) |iter| .{ .iter = iter } else error.NotIterable;
    }
    pub fn deinit(iter: Iter) void {
        c.Py_DecRef(iter.iter);
    }

    pub fn next(iter: Iter, comptime T: type) !?T {
        return if (c.PyIter_Next(iter.iter)) |next_item|
            convert.pyObjectToValue(T, next_item)
        else if (c.PyErr_Occurred() != 0)
            error.AlreadyRaised
        else
            null;
    }
    pub fn nextAny(iter: Iter) !?*anyopaque {
        return if (c.PyIter_Next(iter.iter)) |next_item|
            next_item
        else if (c.PyErr_Occurred() != 0)
            error.AlreadyRaised
        else
            null;
    }
};

pub fn length(list: List) usize {
    return @intCast(c.PyObject_Length(list.py_object));
}
pub fn get(list: List, comptime T: type, index: usize) convert.ParseValueError!T {
    const py_value = list.getAny(index);
    return convert.pyObjectToValue(T, py_value);
}
pub fn sliceOfAny(list: List) [][*c]c.PyObject {
    const py_list: *c.PyListObject = @ptrCast(list.py_object);
    const len: usize = list.length();
    return py_list.ob_item[0..len];
}

pub fn getAny(list: List, index: usize) *c.PyObject {
    @setRuntimeSafety(false); // no point in erroring on the @intCast here.
    if (c.PyList_GetItem(list.py_object, @intCast(index))) |obj| {
        return obj;
    } else {
        // @panic("index out of bounds");
        unreachable;
    }
}
pub fn setAny(list: List, index: usize, value: *c.PyObject) void {
    @setRuntimeSafety(false); // no point in erroring on the @intCast here.

    if (c.PyList_SetItem(list.py_object, @intCast(index), value) == 0) {} else {
        unreachable;
    }
}
pub fn set(list: List, index: usize, value: anytype) void {
    const py_value = convert.valueToPyObject(value);
    list.setAny(index, py_value);
}

pub fn deinit(self: @This()) void {
    c.Py_DecRef(self.py_object);
}
