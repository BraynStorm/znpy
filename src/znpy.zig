const std = @import("std");
pub const options = @import("znpy_options");
pub const c = @import("c.zig").c;

pub const numpy = if (options.numpy_available)
    @import("numpy.zig")
else
    @compileError("Numpy is not available");

pub const List = @import("List.zig");
pub const Function = @import("Function.zig");

const PyObject_HEAD_INIT = 0;
pub const PythonModule = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
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

fn raise(exception: [*c]c.PyObject, message: [:0]const u8) [*c]c.PyObject {
    @branchHint(.cold);
    c.PyErr_SetString(exception, message);
    return null;
}

const convert = @import("convert.zig");
const ParseValueError = convert.ParseValueError;
const pyObjectToValue = convert.pyObjectToValue;
const pythonizeReturnValue = convert.valueToPyObject;

pub fn isMethod(comptime decl_type: type) bool {
    if (@typeInfo(decl_type) != .@"fn") return null;
    const func = @typeInfo(decl_type).@"fn";
    if (func.is_generic) return null;
    if (func.is_var_args) return null;
    if (func.params.len > 1) @compileError("python-accessible functions take exactly 1 struct as an argument");
    if (options.numpy_available)
        if (func.params[0].type.? == numpy.array) @compileError("python-accessible functions take exactly 1 struct as an argument");
    if (@typeInfo(func.params[0].type.?) != .@"struct") @compileError("python-accessible functions take exactly 1 struct as an argument");
    return true;
}

fn raiseFmt(exception: [*c]c.PyObject, comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const message = std.fmt.bufPrintZ(&buf, fmt, args) catch "cant-fit-error-lol";
    _ = raise(exception, message);
}

pub const PyObject = [*c]c.PyObject;

fn exceptionTypeFromError(err: ParseValueError) PyObject {
    return switch (err) {
        ParseValueError.TypeMismatch => c.PyExc_TypeError,
        else => c.PyExc_NotImplementedError,
    };
}

fn raiseFnParamParseError(
    err: ParseValueError,
    fn_name: []const u8,
    param_name: []const u8,
    comptime param_type: type,
) void {
    if (err == error.AlreadyRaised) return;
    raiseFmt(
        exceptionTypeFromError(err),
        "{s} when converting param - [fn {s}(... {s}: {} ...)]",
        .{ @errorName(err), fn_name, param_name, param_type },
    );
}

fn raiseFnReturnParseError(
    err: ParseValueError,
    fn_name: []const u8,
    comptime param_type: type,
) void {
    if (err == error.AlreadyRaised) return;
    raiseFmt(
        exceptionTypeFromError(err),
        "{s} when converting return value - [fn {s}(...) {}]",
        .{ @errorName(err), fn_name, param_type },
    );
}

fn makeMethodDef(
    comptime module: type,
    comptime decl_type: type,
    comptime name: [:0]const u8,
) ?c.PyMethodDef {
    if (!isMethod(decl_type)) return null;
    const func = @typeInfo(decl_type).@"fn";
    const ArgsStruct = func.params[0].type.?;

    //- bs: produce a PyMethodDef for the given function

    //- bs: convert the python parameters to normal parameters for Zig.
    const PyFunc = struct {
        fn wrappedCall(
            self: ?*c.PyObject,
            args: ?*c.PyObject,
            kwargs: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            _ = self;

            const Func = @field(module, name);

            var args_struct: ArgsStruct = undefined;

            //- bs: check for positional arguments
            const tuple = @as(*c.PyTupleObject, @ptrCast(args.?));
            const tuple_size: usize = @intCast(c.PyTuple_Size(args));
            const tuple_items = @as([*][*c]c.PyObject, &tuple.ob_item)[0..tuple_size];
            // var objects_to_kill = [1][*c]c.PyObject{null} ** @typeInfo(ArgsStruct).@"struct".fields.len;
            // defer {
            //     for (objects_to_kill) |o| {
            //         c.Py_XDECREF(o);
            //     }
            // }
            inline for (@typeInfo(ArgsStruct).@"struct".fields, 0..) |field_, i| {
                const field: std.builtin.Type.StructField = field_;
                if (i < tuple_items.len) {
                    //- bs: args
                    @branchHint(.likely);
                    @field(args_struct, field.name) = (pyObjectToValue(field.type, tuple_items[i]) catch |err| {
                        raiseFnParamParseError(
                            err,
                            name,
                            field.name,
                            field.type,
                        );
                        return null;
                    }) orelse {
                        @panic("unsupported parameter function=" ++ name ++ ", parameter=" ++ field.name);
                    };
                } else {
                    @branchHint(.unlikely);
                    //- bs: kwargs + default
                    const py_key = c.PyUnicode_FromStringAndSize(field.name.ptr, field.name.len);
                    defer c.Py_DecRef(py_key);
                    if (c.PyDict_GetItemWithError(kwargs, py_key)) |py_value| {
                        //- bs: we got the value, assign it to the struct
                        // defer c.Py_DECREF(py_value);

                        @field(args_struct, field.name) = pyObjectToValue(field.type, py_value) catch |e| {
                            raiseFnParamParseError(e, name, field.name, field.type);
                            return null;
                        } orelse
                            if (field.defaultValue()) |default|
                                //- bs: set to the default
                                default
                            else {
                                //- bs: no default value, raise an exception. TODO: stacktrace
                                c.PyErr_SetString(c.PyExc_TypeError, "argument count/name mismatch");
                                return null;
                            };
                    } else if (field.defaultValue()) |default| {
                        @field(args_struct, field.name) = default;
                    } else {
                        //- bs: no default value, raise an exception. TODO: stacktrace
                        c.PyErr_SetString(c.PyExc_TypeError, "argument count/name mismatch");
                        return null;
                    }
                }
            }

            if (func.return_type) |rt| {
                const maybe_error_result: rt = @call(.auto, Func, .{args_struct});
                const result = switch (@typeInfo(rt)) {
                    .error_union => maybe_error_result catch |e| {
                        if (@errorReturnTrace()) |stacktrace| {
                            const trace: *std.builtin.StackTrace = stacktrace;
                            var allocating = std.Io.Writer.Allocating.init(py_allocator);
                            defer allocating.deinit();
                            const writer = &allocating.writer;
                            const debug_info = std.debug.getSelfDebugInfo() catch |err| {
                                writer.print("\nUnable to print stack trace: Unable to open debug info: {s}\n", .{@errorName(err)}) catch unreachable;
                                writer.writeByte(0) catch unreachable;
                                return raise(c.PyExc_RuntimeError, @ptrCast(writer.buffered()));
                            };
                            writer.writeAll("\n") catch unreachable;
                            std.debug.writeStackTrace(trace.*, writer, debug_info, .no_color) catch |err| {
                                writer.print("Unable to print stack trace: {s}\n", .{@errorName(err)}) catch unreachable;
                            };
                            writer.writeByte(0) catch unreachable;
                            _ = raise(c.PyExc_RuntimeError, @ptrCast(writer.buffered()));
                        } else {
                            //- bs: no stacktrace, just return the error name.
                            _ = raise(c.PyExc_RuntimeError, @errorName(e));
                        }
                        return null;
                    },
                    else => maybe_error_result,
                };
                return pythonizeReturnValue(result);
            } else {
                //- bs: if it returns nothing, return None.
                @call(.auto, Func, args_struct);
                return c.Py_None();
            }

            return null;
        }
    };
    //- bs: set a good name for this function in the final binary
    @export(&PyFunc.wrappedCall, .{
        .name = name,
    });
    return c.PyMethodDef{
        .ml_name = name,
        .ml_meth = @ptrCast(&PyFunc.wrappedCall),
        .ml_flags = c.METH_VARARGS | c.METH_KEYWORDS,
        .ml_doc = "",
    };
}

fn makeMethodDefsForModule(comptime module: type) []const c.PyMethodDef {
    var defs: []const c.PyMethodDef = &[0]c.PyMethodDef{};

    for (@typeInfo(module).@"struct".decls) |decl| {
        const function_decl = @TypeOf(@field(module, decl.name));
        const method_def = makeMethodDef(module, function_decl, decl.name) orelse continue;
        defs = defs ++ [1]c.PyMethodDef{method_def};
    }

    //- bs: python requires a "null" method, to signal end-of-the-array.
    defs = defs ++ [1]c.PyMethodDef{.{}};
    return defs;
}

const methods: []const c.PyMethodDef = makeMethodDefsForModule(@import("extension_lib"));
var module_def = makeModuleDef();

// reimplemented in Zig because translate-c doesn't handle it well.
const PyModuleDef_HEAD_INIT: c.PyModuleDef_Base = blk: {
    std.debug.assert(options.python_version.major == 3);
    if (options.python_version.minor == 11 or
        options.python_version.minor == 10 or
        options.python_version.minor == 9 or
        options.python_version.minor == 8 or
        options.python_version.minor == 7)
    {
        break :blk .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = null,
            },
            .m_init = null,
            .m_index = 0,
            .m_copy = null,
        };
    }
    if (options.python_version.minor == 14) {
        @compileLog(std.meta.fields(c.union_unnamed_9));
    }
    if (options.python_version.minor == 14 or
        options.python_version.minor == 13 or
        options.python_version.minor == 12)
    {
        break :blk .{
            .ob_base = .{
                .unnamed_0 = .{
                    .ob_refcnt = @as(c.Py_ssize_t, std.math.maxInt(u32) >> 2),
                },
            },
            .m_init = null,
            .m_index = 0,
            .m_copy = null,
        };
    }
};

fn makeModuleDef() c.PyModuleDef {
    return c.PyModuleDef{
        .m_base = PyModuleDef_HEAD_INIT,
        .m_name = options.pyd_name,
        .m_doc = "", // TODO: Add support for doc-comments, on the file/module level.
        .m_size = -1, //- bs: disable sub-interpreters
        .m_methods = @constCast(methods.ptr),
    };
}

fn znpy_PyInit() callconv(.c) [*c]c.PyObject {
    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();

    const extra = if (options.numpy_available)
        std.fmt.comptimePrint(" (Numpy {d}.{d})", .{ options.numpy_version.major, options.numpy_version.minor })
    else
        "";

    stderr.print("znpy: begin initialization of " ++ options.pyd_name ++ ", built for Python {d}.{d}" ++ extra ++ "\n", .{
        options.python_version.major,
        options.python_version.minor,
            // options.python_version.patch,
    }) catch unreachable;

    if (!@hasDecl(@import("root"), "ZNPY_NO_PYINIT")) {
        if (options.numpy_available) {
            _ = c._import_array();
        }
    }

    const module = c.PyModule_Create2(&module_def, c.PYTHON_API_VERSION);
    stderr.print("znpy: initialized: {} \n", .{module != null}) catch unreachable;

    return module;
}

pub fn defineExtensionModule() void {
    if (!@hasDecl(@import("root"), "ZNPY_NO_PYINIT")) {
        @export(&znpy_PyInit, .{ .name = "PyInit_" ++ options.pyd_name, .linkage = .strong });
    }
}

pub const py_allocator = @import("pymalloc.zig").allocator();

pub fn pyLessThan(lhs: PyObject, rhs: PyObject) bool {
    return c.PyObject_RichCompareBool(lhs, rhs, c.Py_LT) != 0;
}
