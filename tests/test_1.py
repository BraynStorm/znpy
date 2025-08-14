import znpy_test
import sys
import numpy as np

for x, y in znpy_test.__dict__.items():
    print(f"{x:20} {y}")

print('--------------------' * 4)
print('znpy_test.magic1:', znpy_test.magic1(20.0, 20.0), file=sys.stderr)
arr = np.ones((5, 2), dtype=np.float32)
print('znpy_test.take_some_array ((5,2);ones)  :', znpy_test.take_some_array(arr), file=sys.stderr)
# print('znpy_test.take_some_array (python int 2):', znpy_test.take_some_array(np.ones((2), dtype=np.float32)), file=sys.stderr)s