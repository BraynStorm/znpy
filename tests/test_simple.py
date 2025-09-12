from typing import Any, Tuple

import test_simple as test


def printAssert(function, expected, args: Tuple[Any], **kwargs):
    value = function(*args, **kwargs)
    print(function.__name__, ":", value)
    assert value == expected, f"\n{value} !=\n{expected}"


def printAssertError(function, expected_error, args: Tuple[Any], **kwargs):
    try:
        printAssert(function, None, args, **kwargs)
    except expected_error:
        pass
    else:
        assert False, "expected to raise an error"


for x, y in test.__dict__.items():
    print(f"{x:20} {y}")

print("--------------------" * 4)

# check for correctly raised errors
printAssertError(test.divide_f32, TypeError, ())
printAssertError(test.divide_f32, TypeError, (20.0))
printAssertError(test.divide_f32, TypeError, (), a=20.0)
printAssertError(test.divide_f32, TypeError, (), b=2.0)

# check for correct values when types match *exactly*
printAssert(test.divide_f32, 4.0, (20.0, 5.0))
printAssert(test.divide_f64, 4.0, (20.0, 5.0))
printAssert(test.divide_f32_default_1, 4.0, (20.0, 5.0))
printAssert(test.divide_f32_default_1, 20.0, (20.0,))
printAssert(test.divide_f32_default_1, 20.0, (), a=20.0)
printAssert(test.divide_f32_default_1, 20.0, (), a=20.0, b=1.0)
printAssert(test.divide_f32_default_1, 10.0, (), a=20.0, b=2.0)

# check for correct values when types sort-of match (expects float, got int)
printAssert(test.divide_f32, 4.0, (20.0, 5))
printAssert(test.divide_f32, 2000.0, (1000, 0.5))
printAssert(test.divide_f32, 4.0, (20, 5))

# # check for optional support
printAssert(test.optional_usize, None, (True,))
printAssert(test.optional_usize, None, ([1, 2],))
printAssert(test.optional_usize, 1, ([],))
printAssert(test.optional_usize, 1, (False,))
printAssert(test.optional_usize, 1, (0,))

# check for immutable bytes support
printAssert(test.sum_bytes, 0 + 1 + 2 + 3, (b"\x00\x01\x02\x03",))

# check for mutable bytes support
some_bytes = bytearray(4)
test.iota_bytes(some_bytes)
print("test.iota_bytes(bytearray(4)) :", some_bytes)
assert some_bytes == b"\x00\x01\x02\x03"

try:
    some_bytes = bytearray(4)
    test.iota_bytes(memoryview(some_bytes))
    print("test.iota_bytes(memoryview(bytearray(4))) :", some_bytes)
    # This would be the expected value
    assert some_bytes == b"\x00\x01\x02\x03"
except NotImplementedError as e:
    print(e)
else:
    assert False

# check for list support
some_list = [6, 4, 1, 10]
test.radix_sort_byte_list(some_list)
print("test.radix_sort_byte_list([6, 4, 1, 10]): ", some_list)
assert some_list == sorted([6, 4, 1, 10])

some_list = [6, 4, 1, 10, 0.3, 0.2, 0.7, -3.14, 3.1]
test.heap_sort_any(some_list)
print("test.heap_sort_any([6, 4, 1, 10, 0.3, 0.2, 0.7, -3.14, 3.1]): ", some_list)
assert some_list == sorted([6, 4, 1, 10, 0.3, 0.2, 0.7, -3.14, 3.1])


def benchmark_sort():
    import timeit
    import random

    rng = []
    for i in range(1024 * 128):
        rng.append(float(i))
        rng.append(float(random.random()))

    print(
        "heap_sort_any:",
        timeit.timeit(lambda: test.heap_sort_any(list(rng)), number=100),
    )
    print("sorted       :", timeit.timeit(lambda: sorted(rng), number=100))


# Enable manually if you want to see the performance :D
# benchmark_sort()
