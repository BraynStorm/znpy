const std = @import("std");
const znpy = @import("znpy");

comptime {
    znpy.defineExtensionModule();
}

fn debug(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn divide_f32(
    args: struct {
        a: f32,
        b: f32,
    },
) f32 {
    return args.a / args.b;
}

pub fn divide_f64(
    args: struct {
        a: f64,
        b: f64,
    },
) f64 {
    return args.a / args.b;
}

pub fn divide_f32_default_1(
    args: struct {
        a: f32,
        b: f32 = 1,
    },
) f32 {
    return args.a / args.b;
}

pub fn optional_usize(args: struct { return_nothing: bool }) ?usize {
    return if (args.return_nothing) null else 1;
}

pub fn sum_bytes(args: struct { bytes: []const u8 }) usize {
    var sum: usize = 0;

    for (args.bytes) |b| {
        sum += @as(usize, b);
    }

    return sum;
}

pub fn iota_bytes(args: struct { bytes: []u8 }) void {
    for (0.., args.bytes) |i, *b| {
        b.* = @truncate(i);
    }
}

pub fn radix_sort_byte_list(args: struct { list: znpy.List }) !void {
    var radix_sort_arr = [1]usize{0} ** 256;

    //- bs: count/copy all the items
    {
        const iter = try znpy.List.Iter.init(args.list);
        defer iter.deinit();
        var i: usize = 0;
        while (try iter.next(u8)) |item| : (i += 1) {
            radix_sort_arr[item] += 1;
        }
    }

    //- bs: write-back all the items.
    var index: usize = 0;
    for (radix_sort_arr, 0..) |count, value| {
        for (0..count) |_| {
            args.list.set(index, value);
            index += 1;
        }
    }
}

pub fn heap_sort_any(args: struct { list: znpy.List }) void {
    const PyObject = @TypeOf(args.list.sliceOfAny()[0]);
    std.sort.heap(PyObject, args.list.sliceOfAny(), {}, struct {
        pub fn lessThan(ctx: void, lhs: PyObject, rhs: PyObject) bool {
            _ = ctx; // autofix
            return znpy.pyLessThan(lhs, rhs);
        }
    }.lessThan);
}

pub fn repeat_string(args: struct { count: u32 }) !znpy.String {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    _ = writer.splatByte('5', args.count) catch unreachable;
    writer.flush() catch unreachable;
    return .fromBuffer(writer.buffered());
}

pub fn dict_concat_keys(args: struct { data: znpy.Dict }) !znpy.String {
    const key_list = args.data.keys();
    defer key_list.deinit();

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    for (key_list.sliceOfAny()) |anything| {
        if (try znpy.convert.pyObjectToValue(u32, anything)) |number| {
            try writer.print("{d}", .{number});
        } else if (try znpy.convert.pyObjectToValue([]const u8, anything)) |string| {
            try writer.writeAll(string);
        } else {
            return error.UnknownType;
        }
        try writer.writeByte(',');
    }

    if (writer.buffered().len > 0)
        writer.undo(1);

    writer.flush() catch unreachable;
    return .fromBuffer(writer.buffered());
}
pub fn dict_sum_values(args: struct { data: znpy.Dict }) !usize {
    const value_list = args.data.values();
    defer value_list.deinit();

    var sum: usize = 0;
    for (value_list.sliceOfAny()) |anything| {
        if (try znpy.convert.pyObjectToValue(usize, anything)) |number| {
            sum += number;
        } else {
            return error.UnknownType;
        }
    }
    return sum;
}
