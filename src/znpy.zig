const std = @import("std");

/// CPython!
pub const c = @cImport({
    @cInclude("Python.h");
    @cInclude("numpy/arrayobject.h");
});

const PyObject_HEAD_INIT = 0;
const root = @import("root");
pub const PythonModule = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
};

pub const numpy = struct {
    pub const Error = error{
        TypeMismatch,
        DimensionsMismatch,
    };
    pub const array = struct {
        ndarray: *c.PyArrayObject,

        const Untyped = @This();

        fn n_dims(self: Untyped) usize {
            return @intCast(self.ndarray.nd);
        }

        pub fn shape(self: Untyped) []isize {
            return self.ndarray.dimensions[0..self.n_dims()];
        }

        pub fn strides(self: Untyped) []isize {
            return self.ndarray.strides[0..self.n_dims()];
        }

        fn withTypeAndDims_Impl(comptime dtype: type, comptime ndims: usize) type {
            // self.ndarray.data
            return struct {
                untyped: Untyped,
                const Typed = @This();

                pub const DType = dtype;
                pub const NDims = ndims;

                pub const Index = @Vector(NDims, usize);
                pub const Index1D = @Vector(NDims - 1, usize);

                pub fn init(untyped: Untyped) !Typed {
                    if (untyped.shape().len != NDims) return Error.DimensionsMismatch;
                    const py_dtype = c.PyArray_TYPE(untyped.ndarray);
                    _ = py_dtype; // autofix

                    return .{ .untyped = untyped };
                }

                pub fn shape(self: Typed) []isize {
                    return self.untyped.shape();
                }

                pub fn strides(self: Typed) []isize {
                    return self.untyped.strides();
                }

                pub fn slice1d(self: Typed, index: Index1D) []const DType {
                    var i: usize = 0;
                    const shape_ = self.shape();
                    const strides_ = self.strides();
                    _ = strides_; // autofix

                    inline for (0..NDims) |d| {
                        i += shape_[d] * index[d];
                    }

                    return self.untyped.ndarray.data[i .. i + index];
                }

                fn n_dims(self: Typed) usize {
                    _ = self; // autofix
                    return NDims;
                }
            };
        }

        pub fn withTypeAndDims(
            self: Untyped,
            comptime DType: type,
            comptime NDims: usize,
        ) withTypeAndDims_Impl(DType, NDims) {
            return withTypeAndDims_Impl(DType, NDims).init(self);
        }

        pub fn iter(self: Untyped, comptime ValueT: type, comptime NDims: usize) type {
            _ = self; // autofix
            _ = ValueT; // autofix
            _ = NDims; // autofix
            return struct {
                const Iter = @This();

                // pub fn next()
            };
        }
    };
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

const methods: []const c.PyMethodDef = blk: {
    var defs: []const c.PyMethodDef = &[0]c.PyMethodDef{};

    for (std.meta.declarations(root)) |root_decl_name| {
        const root_decl = @TypeOf(@field(root, root_decl_name.name));
        if (@typeInfo(root_decl) != .@"fn") continue;
        const func = @typeInfo(root_decl).@"fn";
        if (func.is_generic) continue;
        if (func.is_var_args) continue;

        //- bs: produce a PyMethodDef for the given function

        //- bs: convert the python parameters to normal parameters for Zig.
        const PyFunc = struct {
            fn callConverted(self: ?*c.PyObject, args: ?*c.PyObject) callconv(.c) ?*c.PyObject {
                _ = self; // autofix
                const Func = @field(root, root_decl_name.name);

                const ArgsTuple = std.meta.ArgsTuple(root_decl);
                var args_tuple: ArgsTuple = undefined;

                //- bs: check for positional arguments
                if (check(c.PyTuple_Check, .{args})) {
                    const tuple = @as(*c.PyTupleObject, @ptrCast(args.?));
                    const tuple_size: usize = @intCast(c.PyTuple_Size(args));
                    const tuple_items = @as([*][*c]c.PyObject, &tuple.ob_item)[0..tuple_size];
                    inline for (func.params, &args_tuple, 0..) |p, *t, i| {
                        std.debug.assert(p.type != null);

                        const py_arg: ?*c.PyObject = tuple_items[i];
                        switch (@typeInfo(@TypeOf(t.*))) {
                            .int => {
                                std.debug.assert(check(c.PyLong_Check, .{py_arg}));
                                const number = c.PyLong_AsUnsignedLong(py_arg);
                                t.* = @intCast(number);
                            },
                            .float => {
                                std.debug.assert(check(c.PyFloat_Check, .{py_arg}));
                                const number = c.PyFloat_AsDouble(py_arg);
                                t.* = @floatCast(number);
                            },
                            .@"struct" => {
                                if (@TypeOf(t.*) == numpy.array) {
                                    if (std.meta.eql(
                                        @as(usize, @intFromPtr(@as([*c]?*c.PyTypeObject, @ptrCast(c.PyArray_API))[2])),
                                        @as(usize, @intFromPtr(py_arg.?.ob_type)),
                                    )) {
                                        t.* = numpy.array{ .ndarray = @as(*c.PyArrayObject, @ptrCast(py_arg)) };
                                    } else {
                                        @panic("non-ndarray input!");
                                    }
                                } else {
                                    @compileError("unknown struct");
                                }
                            },
                            else => {
                                @compileLog("unknown type of argument:");
                                @compileLog(root_decl_name.name, i, t.*);
                            },
                        }
                    }
                }

                if (func.return_type) |rt| {
                    const result: rt = @call(.auto, Func, args_tuple);

                    return switch (@typeInfo(rt)) {
                        .int => |int_t| switch (int_t.signedness) {
                            .signed => c.PyLong_FromLongLong(@intCast(result)),
                            .unsigned => c.PyLong_FromUnsignedLongLong(@intCast(result)),
                        },
                        .float => c.PyFloat_FromDouble(result),
                        else => @compileError("Unsupported return type (yet!)"),
                    };
                } else {
                    //- bs: if it returns nothing, return None.

                    @call(.auto, Func, args_tuple);
                    return c.Py_None();
                }

                return null;
            }
        };

        defs = defs ++ [1]c.PyMethodDef{c.PyMethodDef{
            .ml_name = root_decl_name.name,
            .ml_meth = &PyFunc.callConverted,
            .ml_flags = c.METH_VARARGS,
            .ml_doc = "",
        }};
    }

    //- bs: python requires a "null" method, to signal end-of-the-array.
    defs = defs ++ [1]c.PyMethodDef{.{}};
    break :blk defs;
};
var module_def_spec = makeModuleDef();

fn makeModuleDef() c.PyModuleDef {
    return c.PyModuleDef{
        .m_base = .{
            .ob_base = .{
                // ---- for py 3.13
                // .unnamed_0 = .{
                //     .ob_refcnt = @as(c.Py_ssize_t, std.math.maxInt(u32) >> 2),
                // },
                // ----- for py 3.7
                .ob_refcnt = 1,
                .ob_type = null,
            },
            .m_init = null,
            .m_index = 0,
            .m_copy = null,
        },
        .m_name = root.python_module.name,
        .m_doc = root.python_module.doc,
        .m_size = -1, //- bs: disable sub-interpreters
        .m_methods = @constCast(methods.ptr),
    };
}

fn znpy_PyInit() callconv(.c) [*c]c.PyObject {
    const module = c.PyModule_Create(&module_def_spec);
    _ = c._import_array();
    return module;
}

comptime {
    @export(&znpy_PyInit, .{
        .name = "PyInit_" ++ root.python_module.name,
        .linkage = .strong,
    });
}
