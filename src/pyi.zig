const std = @import("std");
const builtin = @import("builtin");
const extension_lib = @import("extension_lib");
const znpy = @import("znpy");

//- bs: prevent linking to Python and related
pub const ZNPY_NO_PYINIT = {};

const has_better_optional =
    znpy.options.python_version.major == 3 and
    znpy.options.python_version.minor >= 11;

fn pythonizeParamType(
    comptime param_type: type,
    writer: anytype,
    depth: u32,
) !void {
    switch (@typeInfo(param_type)) {
        .int => try writer.writeAll(": int"),
        .float => try writer.writeAll(": float"),
        .@"struct" => {
            if (znpy.options.numpy_available) {
                const numpy = znpy.numpy;

                if (param_type == numpy.array) {
                    try writer.writeAll(": np.ndarray");
                }
            }
        },
        .optional => |opt| {
            if (!has_better_optional)
                try writer.writeAll(": Optional[");
            try pythonizeParamType(opt.child, writer, depth + 1);
            if (has_better_optional) try writer.writeAll(" | None");
            if (!has_better_optional)
                try writer.writeAll("]");
        },
        .bool => {
            try writer.writeAll(": bool");
        },
        .pointer => |pp| {
            switch (pp.size) {
                .slice => {
                    try writer.writeAll(": bytes");
                },
                else => unreachable,
            }
        },
        else => @compileLog(param_type),
    }
}

fn pythonizeReturnType(comptime return_type: type, writer: *std.Io.Writer) !void {
    switch (@typeInfo(return_type)) {
        .int => try writer.writeAll("int"),
        .float => try writer.writeAll("float"),
        .bool => try writer.writeAll("bool"),
        .optional => |opt| {
            if (!has_better_optional)
                try writer.writeAll("Optional[");
            try pythonizeReturnType(opt.child, writer);
            if (has_better_optional) try writer.writeAll(" | None");
            if (!has_better_optional)
                try writer.writeAll("]");
        },
        .void => try writer.writeAll("None"),
        else => {
            @compileLog(return_type);
            @compileError("pyi - unsupported return type");
        },
    }
}

/// main() for generating a python interface file (.pyi)
/// for the extension module.
///
pub fn main() !void {
    var buffer: [64]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch unreachable;

    // TODO: figure out a more granular way of importing these.
    if (!has_better_optional)
        try out.writeAll("from typing import Optional\n\n");

    if (znpy.options.numpy_available)
        try out.writeAll("import numpy as np\n\n");

    inline for (@typeInfo(extension_lib).@"struct".decls) |decl| {
        const decl_type = @TypeOf(@field(extension_lib, decl.name));
        if (znpy.isMethod(decl_type)) {
            const func = @typeInfo(decl_type).@"fn";
            const ArgsStruct = func.params[0].type.?;

            //- bs: function name
            try out.print("def {s}(", .{decl.name});
            const params = @typeInfo(ArgsStruct).@"struct".fields;

            const split_line_by_line = params.len > 2;

            //- bs: parameters
            if (split_line_by_line) {
                try out.writeByte('\n');
            }
            inline for (0.., params) |i, param| {
                if (split_line_by_line) {
                    try out.writeByte('\t');
                }
                try out.writeAll(param.name);
                try pythonizeParamType(param.type, out, 0);

                if (split_line_by_line) {
                    try out.writeAll(",\n");
                } else {
                    if (i != params.len - 1) {
                        try out.writeAll(", ");
                    }
                }
            }

            try out.writeByte(')');

            //- bs: return type
            try out.writeAll(" -> ");
            if (func.return_type) |rt| {
                const return_type = switch (@typeInfo(rt)) {
                    .error_union => |eu| eu.payload,
                    else => rt,
                };
                try pythonizeReturnType(return_type, out);
            } else {
                try out.writeAll("None");
            }
            try out.writeAll(": pass\n");
        }
    }
}
