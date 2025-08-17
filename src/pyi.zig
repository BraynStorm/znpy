const std = @import("std");
const builtin = @import("builtin");
const extension_lib = @import("extension_lib");
const znpy = @import("znpy");

//- bs: prevent linking to Python and related
pub const ZNPY_NO_PYINIT = {};

fn pythonizeParamType(
    comptime param_type: type,
    writer: anytype,
    depth: u32,
) !void {
    switch (@typeInfo(param_type)) {
        .int => try writer.writeAll(": int"),
        .float => try writer.writeAll(": float"),
        .@"struct" => {
            const numpy = znpy.numpy;

            if (param_type == numpy.array) {}
        },
        .optional => |opt| {
            try writer.writeAll(": Optional[");
            try pythonizeParamType(opt.child, writer, depth + 1);
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
    // if(param.default_value_ptr)

}

fn pythonizeReturnType(comptime return_type: type, out: anytype) !void {
    switch (@typeInfo(return_type)) {
        .int => try out.writeAll("int"),
        .float => try out.writeAll("float"),
        .bool => try out.writeAll("bool"),
        .optional => |opt| {
            try out.writeAll("Optional[");
            try pythonizeReturnType(opt.child, out);
            try out.writeAll("]");
        },
        .void => try out.writeAll("None"),
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
    const stdout = std.io.getStdOut();
    try stdout.lock(.exclusive);

    const out = stdout.writer();

    // TODO: figure out a more granular way of importing these.
    try out.writeAll("from typing import Optional\n\n");

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
