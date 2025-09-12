const c = @import("c.zig").c;

pub const Error = error{
    TypeMismatch,
    DimensionsMismatch,
    NegativeDimension,
    NegativeStride,
};
const PyDTYPE = enum(c.NPY_TYPES) {
    NPY_BOOL = 0,
    NPY_BYTE,
    NPY_UBYTE,
    NPY_SHORT,
    NPY_USHORT,
    NPY_INT,
    NPY_UINT,
    NPY_LONG,
    NPY_ULONG,
    NPY_LONGLONG,
    NPY_ULONGLONG,
    NPY_FLOAT,
    NPY_DOUBLE,
    NPY_LONGDOUBLE,
    NPY_CFLOAT,
    NPY_CDOUBLE,
    NPY_CLONGDOUBLE,
    NPY_OBJECT = 17,
    NPY_STRING,
    NPY_UNICODE,
    NPY_VOID,
    // /*
    //  * New 1.6 types appended, may be integrated
    //  * into the above in 2.0.
    //  */
    NPY_DATETIME,
    NPY_TIMEDELTA,
    NPY_HALF,

    // NPY_CHAR, /* Deprecated, will raise if used */

    // /* The number of *legacy* dtypes */
    // NPY_NTYPES_LEGACY = 24,

    // /* assign a high value to avoid changing this in the
    //    future when new dtypes are added */
    // NPY_NOTYPE = 25,

    // NPY_USERDEF = 256, //  /* leave room for characters */

    // /* The number of types not including the new 1.6 types */
    // NPY_NTYPES_ABI_COMPATIBLE = 21,

    // /*
    //  * New DTypes which do not share the legacy layout
    //  * (added after NumPy 2.0).  VSTRING is the first of these
    //  * we may open up a block for user-defined dtypes in the
    //  * future.
    //  */
    // NPY_VSTRING = 2056,
};

pub const array = struct {
    ndarray: *c.PyArrayObject,

    const Untyped = @This();

    fn n_dims(self: Untyped) usize {
        return @intCast(self.ndarray.nd);
    }

    pub fn shape(self: Untyped) []isize {
        return self.ndarray.dimensions[0..@intCast(self.ndarray.nd)];
    }

    pub fn strides(self: Untyped) []isize {
        return self.ndarray.strides[0..self.n_dims()];
    }

    pub fn dtype(self: Untyped) PyDTYPE {
        return @enumFromInt(c.PyArray_TYPE(self.ndarray));
    }

    pub fn typed(comptime T: type, comptime dims: usize) type {
        return struct {
            untyped: Untyped,
            const Typed = @This();

            pub const DType = T;
            pub const NDims = dims;

            pub const Index = @Vector(NDims, usize);
            pub const Index1D = @Vector(NDims - 1, usize);

            pub fn init(untyped: Untyped) !Typed {
                const shape_ = untyped.shape();
                if (shape_.len != NDims) return Error.DimensionsMismatch;
                for (shape_) |d| if (d < 0) return Error.NegativeDimension;
                for (untyped.strides()) |d| if (d <= 0) return Error.NegativeStride;

                const py_dtype = untyped.dtype();
                switch (DType) {
                    // c.NPY_TYPES
                    f32 => if (py_dtype != .NPY_FLOAT) return Error.TypeMismatch,
                    f64 => if (py_dtype != .NPY_DOUBLE) return Error.TypeMismatch,
                    else => @compileError("Unsupported dtype (yet!)"),
                }
                return .{ .untyped = untyped };
            }

            pub fn shape(self: Typed) []usize {
                return @ptrCast(self.untyped.shape());
            }

            pub fn strides(self: Typed) []usize {
                return @ptrCast(self.untyped.strides());
            }

            pub fn slice1d(self: Typed, index: Index1D) []align(1) const DType {
                const shape_ = self.shape();
                const strides_ = self.strides();
                const data_: [*]align(1) const DType = @ptrCast(self.untyped.ndarray.data);

                var i: usize = 0;
                inline for (0..NDims - 1) |d| {
                    i += @divExact(strides_[d], @sizeOf(DType)) * index[d];
                }

                const type_slice = data_[i .. i + shape_[shape_.len - 1]];
                return type_slice;
            }

            fn n_dims(self: Typed) usize {
                _ = self;
                return NDims;
            }
        };
    }

    pub fn withTypeAndDims(
        self: Untyped,
        comptime T: type,
        comptime dims: usize,
    ) !typed(T, dims) {
        return try typed(T, dims).init(self);
    }
};
