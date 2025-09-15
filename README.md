# ZNPY

Write extensions modules for Python 3.7+ in Zig instead of C.

## Example

Simple and contrived:
```zig
const std = @import("std");
const znpy = @import("znpy");

comptime {
    znpy.defineExtensionModule();
}

pub fn divide_f32_default_1(
    args: struct {
        a: f32,
        b: f32 = 1,
    },
) f32 {
    return args.a / args.b;
}


```

## Exhaustive feature list

- Tested on Python versions: 3.7, 3.8, 3.9, 3.10, 3.11, 3.12, 3.13
    - on Alpine Linux
    - on Arch Linux
    - on Windows 11
- Test on Numpy versions: [1.21 to 2.3] (API seems stable enough)

- Supported argument types:
    - 'bool'
        - auto-conversion from `object.__bool__()`
    - signed/unsigned integers - u8, u16, u32, u64, i8, i16, i32, i64
        - auto-conversion from `number`-like things
    - single/double precision floats - f32, f64
        - auto-conversion from `number`-like things
    - 'str' (immutable)
    - 'bytes' (immutable)
    - 'bytearray' (mutable)
    - 'numpy.ndarray' (mutable)
    - 'list' (mutable)
    - 'dict' (mutable)

- Supported return types:
    - void
    - 'bool'
    - signed/unsigned integers - u8, u16, u32, u64, i8, i16, i32, i64
    - single/double precision floats - f32, f64

- Supports `Optional[T]` on most parameters and all return types (except void, duh).
- Supports converting Zig errors to Python Exceptions.
- Supports keyword arguments

## Not supported yet (WIP)

- Arguments:
    - 'iterable'
    - 'memoryview' (mutable/immutable)
    - 'file-descriptor' (file, socket, etc.)
    - streams (io.BytesIO, etc.)
    - custom data types
- Return values:
    - 'numpy.ndarray'
    - 'bytes' / 'bytearray'
    - 'list' / 'tuple' / 'dict'
    - custom data types
- QoL:
    - auto-conversion from array-like to numpy.ndarray
