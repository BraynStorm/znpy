from typing import Any, Tuple
import znpy_test_simple as znpy_test

def printAssert(function, expected, args: Tuple[Any], **kwargs):
    value = function(*args, **kwargs)
    print(function.__name__, ':', value)
    assert value == expected, f"\n{value} !=\n{expected}"

def printAssertError(function, expected_error, args: Tuple[Any], **kwargs):
    try:
        printAssert(function, None, args, **kwargs)
    except expected_error:
        pass
    else:
        assert False, "expected to raise an error"

for x, y in znpy_test.__dict__.items():
    print(f"{x:20} {y}")

print('--------------------' * 4)

# check for correctly raised errors
printAssertError(znpy_test.divide_f32, TypeError, ())
printAssertError(znpy_test.divide_f32, TypeError, (20.0))
printAssertError(znpy_test.divide_f32, TypeError, (), a=20.0)
printAssertError(znpy_test.divide_f32, TypeError, (), b=2.0)

# check for correct values when types match *exactly*
printAssert(znpy_test.divide_f32, 4.0, (20.0, 5.0))
printAssert(znpy_test.divide_f32_default_1, 4.0, (20.0, 5.0))
printAssert(znpy_test.divide_f32_default_1, 20.0, (20.0, ))
printAssert(znpy_test.divide_f32_default_1, 20.0, (), a=20.0)
printAssert(znpy_test.divide_f32_default_1, 20.0, (), a=20.0, b=1.0)
printAssert(znpy_test.divide_f32_default_1, 10.0, (), a=20.0, b=2.0)

# check for correct values when types sort-of match (expects float, got int)
printAssert(znpy_test.divide_f32, 4.0, (20.0, 5))
printAssert(znpy_test.divide_f32, 2000.0, (1000, 0.5))
printAssert(znpy_test.divide_f32, 4.0, (20, 5))
