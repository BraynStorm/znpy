import numpy as np
import test_numpy as test

for x, y in test.__dict__.items():
    print(f"{x:20} {y}")

print("--------------------" * 4)
arr = np.ones((5), dtype=np.float32)
print("test.take_some_array ((5); ones)      :", test.take_some_array(arr))
arr = np.ones((5, 4), dtype=np.float32)
print("test.take_some_array ((5, 4); ones)   :", test.take_some_array(arr))
arr = np.ones((5, 2, 4), dtype=np.float32)
print("test.take_some_array ((5, 2, 4); ones):", test.take_some_array(arr))

arr = np.ones((512, 512, 512), dtype=np.float32)
print("test.take_some_array ((512, 512, 512); ones):", test.take_some_array(array=arr))

# arr = [1.0,2.0,3.0]
# print('test.take_some_array ([1.0, 2.0, 3.0]):', test.take_some_array(arr))

# arr = np.ones((512, 512, 512), dtype=np.float32)
# import timeit
# print("(pref) my impl:", timeit.timeit(lambda: test.take_some_array(arr), number=100))
# print("(pref) np impl:", timeit.timeit(lambda: np.sum(arr), number=100))


# arr = np.ones((5, 3, 2, 5), dtype=np.float32)
# print('test.take_some_array ((5, 3, 2, 5); ones):', test.take_some_array(arr))
