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
        NegativeDimension,
        NegativeStride,
    };
    const PyDTYPE = enum(c.NPY_TYPES) {
        NPY_BOOL = 0,
        NPY_BYTE,
        NPY_UBYTE,
        NPY_SHORT,
        NPY_USHORT,
        NPY_INT,
        NPY_UINT,
        NPY_LONG,
        NPY_ULONG,
        NPY_LONGLONG,
        NPY_ULONGLONG,
        NPY_FLOAT,
        NPY_DOUBLE,
        NPY_LONGDOUBLE,
        NPY_CFLOAT,
        NPY_CDOUBLE,
        NPY_CLONGDOUBLE,
        NPY_OBJECT = 17,
        NPY_STRING,
        NPY_UNICODE,
        NPY_VOID,
        // /*
        //  * New 1.6 types appended, may be integrated
        //  * into the above in 2.0.
        //  */
        NPY_DATETIME,
        NPY_TIMEDELTA,
        NPY_HALF,

        // NPY_CHAR, /* Deprecated, will raise if used */

        // /* The number of *legacy* dtypes */
        // NPY_NTYPES_LEGACY = 24,

        // /* assign a high value to avoid changing this in the
        //    future when new dtypes are added */
        // NPY_NOTYPE = 25,

        // NPY_USERDEF = 256, //  /* leave room for characters */

        // /* The number of types not including the new 1.6 types */
        // NPY_NTYPES_ABI_COMPATIBLE = 21,

        // /*
        //  * New DTypes which do not share the legacy layout
        //  * (added after NumPy 2.0).  VSTRING is the first of these
        //  * we may open up a block for user-defined dtypes in the
        //  * future.
        //  */
        // NPY_VSTRING = 2056,
    };

    pub const array = struct {
        ndarray: *c.PyArrayObject,

        const Untyped = @This();

        fn n_dims(self: Untyped) usize {
            return @intCast(self.ndarray.nd);
        }

        pub fn shape(self: Untyped) []isize {
            return self.ndarray.dimensions[0..@intCast(self.ndarray.nd)];
        }

        pub fn strides(self: Untyped) []isize {
            return self.ndarray.strides[0..self.n_dims()];
        }

        pub fn dtype(self: Untyped) PyDTYPE {
            return @enumFromInt(c.PyArray_TYPE(self.ndarray));
        }

        pub fn typed(comptime T: type, comptime dims: usize) type {
            return struct {
                untyped: Untyped,
                const Typed = @This();

                pub const DType = T;
                pub const NDims = dims;

                pub const Index = @Vector(NDims, usize);
                pub const Index1D = @Vector(NDims - 1, usize);

                pub fn init(untyped: Untyped) !Typed {
                    const shape_ = untyped.shape();
                    if (shape_.len != NDims) return Error.DimensionsMismatch;
                    for (shape_) |d| if (d < 0) return Error.NegativeDimension;
                    for (untyped.strides()) |d| if (d <= 0) return Error.NegativeStride;

                    const py_dtype = untyped.dtype();
                    switch (DType) {
                        // c.NPY_TYPES
                        f32 => if (py_dtype != .NPY_FLOAT) return Error.TypeMismatch,
                        f64 => if (py_dtype != .NPY_DOUBLE) return Error.TypeMismatch,
                        else => @compileError("Unsupported dtype (yet!)"),
                    }
                    return .{ .untyped = untyped };
                }

                pub fn shape(self: Typed) []usize {
                    return @ptrCast(self.untyped.shape());
                }

                pub fn strides(self: Typed) []usize {
                    return @ptrCast(self.untyped.strides());
                }

                pub fn slice1d(self: Typed, index: Index1D) []align(1) const DType {
                    const shape_ = self.shape();
                    const strides_ = self.strides();
                    const data_: [*]align(1) const DType = @ptrCast(self.untyped.ndarray.data);

                    var i: usize = 0;
                    inline for (0..NDims - 1) |d| {
                        i += @divExact(strides_[d], @sizeOf(DType)) * index[d];
                    }

                    // std.debug.print("shape = {any}\n", .{shape_});
                    // std.debug.print("strides = {any}\n", .{strides_});
                    const type_slice = data_[i .. i + shape_[shape_.len - 1]];
                    return type_slice;
                }

                fn n_dims(self: Typed) usize {
                    _ = self; // autofix
                    return NDims;
                }
            };
        }

        pub fn withTypeAndDims(
            self: Untyped,
            comptime T: type,
            comptime dims: usize,
        ) !typed(T, dims) {
            return try typed(T, dims).init(self);
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
            fn callConverted(
                self: ?*c.PyObject,
                args: ?*c.PyObject,
                kwargs: ?*c.PyObject,
            ) callconv(.c) ?*c.PyObject {
                _ = self; // autofix
                _ = kwargs; // autofix
                const Func = @field(root, root_decl_name.name);

                const ArgsTuple = std.meta.ArgsTuple(root_decl);
                var args_tuple: ArgsTuple = undefined;

                //- bs: check for positional arguments
                const tuple = @as(*c.PyTupleObject, @ptrCast(args.?));
                const tuple_size: usize = @intCast(c.PyTuple_Size(args));
                const tuple_items = @as([*][*c]c.PyObject, &tuple.ob_item)[0..tuple_size];
                inline for (func.params, &args_tuple, 0..) |p, *t, i| {
                    std.debug.assert(p.type != null);

                    //- bs: stop parsing, there may be kwargs, though!
                    if (i >= tuple_items.len) break;

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

                //- bs: kwargs!
                inline for (func.params, &args_tuple, 0..) |p, *t, i| {
                    _ = p; // autofix
                    _ = t; // autofix
                    if (i > tuple_size) {
                        //- bs: check if it's in kwargs

                        // c.PyDict_GetItem(kwargs, )

                        //
                    } else {
                        //
                    }
                }
                if (func.return_type) |rt| {
                    const maybe_error_result: rt = @call(.auto, Func, args_tuple);
                    const result_t = switch (@typeInfo(rt)) {
                        .error_union => |e| e.payload,
                        else => rt,
                    };
                    const result = switch (@typeInfo(rt)) {
                        .error_union => maybe_error_result catch |e| {
                            if (@errorReturnTrace()) |stacktrace| {
                                const trace: *std.builtin.StackTrace = stacktrace;
                                const alloc = std.heap.c_allocator;
                                var array = std.ArrayListUnmanaged(u8).initCapacity(alloc, 4096) catch unreachable;
                                defer array.deinit(alloc);

                                const writer = array.writer(alloc);
                                const debug_info = std.debug.getSelfDebugInfo() catch |err| {
                                    writer.print("\nUnable to print stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch unreachable;
                                    writer.writeByte(0) catch unreachable;
                                    c.PyErr_SetString(c.PyExc_RuntimeError, array.items.ptr);
                                    return null;
                                };
                                writer.writeAll("\n") catch unreachable;
                                std.debug.writeStackTrace(trace.*, writer, debug_info, .no_color) catch |err| {
                                    writer.print("Unable to print stack trace: {s}\n", .{@errorName(err)}) catch unreachable;
                                };
                                writer.writeByte(0) catch unreachable;
                                c.PyErr_SetString(c.PyExc_RuntimeError, array.items.ptr);
                            } else {
                                //- bs: no stacktrace, just return the error name.
                                c.PyErr_SetString(c.PyExc_RuntimeError, @errorName(e));
                            }
                            return null;
                        },
                        else => maybe_error_result,
                    };

                    return switch (@typeInfo(result_t)) {
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
            .ml_meth = @ptrCast(&PyFunc.callConverted),
            .ml_flags = c.METH_VARARGS | c.METH_KEYWORDS,
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
                .unnamed_0 = .{
                    .ob_refcnt = @as(c.Py_ssize_t, std.math.maxInt(u32) >> 2),
                },
                // ----- for py 3.7
                // .ob_refcnt = 1,
                // .ob_type = null,
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
