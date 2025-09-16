const std = @import("std");
const znpy = @import("znpy");

comptime {
    znpy.defineExtensionModule();
}

fn debug(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn callback_with_args(args: struct {
    a: isize,
    b: isize,
    callback: znpy.Function,
}) !isize {
    const r = try znpy.convert.pyObjectToValue(
        isize,
        args.callback.call_v1(.{ args.a, args.b }, .{}),
    ) orelse unreachable;
    return r;
}
