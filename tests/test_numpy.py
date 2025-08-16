import znpy_test_numpy as znpy_test
import numpy as np

for x, y in znpy_test.__dict__.items():
    print(f"{x:20} {y}")

print('--------------------' * 4)
arr = np.ones((5), dtype=np.float32)
print('znpy_test.take_some_array ((5); ones)      :', znpy_test.take_some_array(arr))
arr = np.ones((5, 4), dtype=np.float32)
print('znpy_test.take_some_array ((5, 4); ones)   :', znpy_test.take_some_array(arr))
arr = np.ones((5, 2, 4), dtype=np.float32)
print('znpy_test.take_some_array ((5, 2, 4); ones):', znpy_test.take_some_array(arr))

arr = np.ones((512, 512, 512), dtype=np.float32)
print('znpy_test.take_some_array ((512, 512, 512); ones):', znpy_test.take_some_array( array=arr))

print('znpy_test.magic2(a=4,b=2):', znpy_test.magic2(a=4, b=2))
print('znpy_test.magic2(b=4,a=2):', znpy_test.magic2(b=4, a=2))
print('znpy_test.magic2(a=4):', znpy_test.magic2(a=4))

# arr = np.ones((512, 512, 512), dtype=np.float32)
# import timeit
# print("(pref) my impl:", timeit.timeit(lambda: znpy_test.take_some_array(arr), number=100))
# print("(pref) np impl:", timeit.timeit(lambda: np.sum(arr), number=100))


# arr = np.ones((5, 3, 2, 5), dtype=np.float32)
# print('znpy_test.take_some_array ((5, 3, 2, 5); ones):', znpy_test.take_some_array(arr))