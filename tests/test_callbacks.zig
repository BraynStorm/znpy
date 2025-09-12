const std = @import("std");
const znpy = @import("znpy");

comptime {
    znpy.defineExtensionModule();
}

fn debug(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn callback_with_args(args: struct {}) void {
    _ = args; // autofix

}
