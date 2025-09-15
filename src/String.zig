//! Represents a text object (`str`) returned to Python.
//!
//! Use the static .fromXXX() to construct.

const c = @import("c.zig").c;

const String = @This();

py_object: *c.PyObject,

/// Convert a Zig buffer to a Python string.
/// This creates a copy of the memory, owned by Python, so the `buffer` can be
/// freed after this call.
pub fn fromBuffer(buffer: []const u8) !@This() {
    const py_string = c.PyUnicode_FromStringAndSize(buffer.ptr, @intCast(buffer.len));
    if (py_string == null) {
        return error.PyOOM;
    }
    return .{ .py_object = py_string };
}

pub fn deinit(self: @This()) void {
    _ = self;
    @panic("DON'T! it's not ready");
}
