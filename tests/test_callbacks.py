from typing import Any, Tuple

import test_callbacks as test


def printAssert(function, expected, args: Tuple[Any], **kwargs):
    value = function(*args, **kwargs)
    print(function.__name__, ":", value)
    assert value == expected, f"\n{value} !=\n{expected}"


printAssert(test.callback_with_args, 1 + 3, (1, 3, (lambda x, y: x + y)))
