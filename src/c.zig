const options = @import("znpy_options");

/// CPython!
pub const c = @cImport({
    @cInclude("Python.h");
    if (options.numpy_available)
        @cInclude("numpy/arrayobject.h");
});
