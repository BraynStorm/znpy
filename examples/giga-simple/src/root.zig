comptime {
    @import("znpy").defineExtensionModule();
}

pub fn add(args: struct { a: i32, b: i32 }) i32 {
    return args.a + args.b;
}
