FROM python:3.7-alpine
RUN apk add curl
RUN curl https://ziglang.org/download/0.14.1/zig-x86_64-linux-0.14.1.tar.xz -o zig.tar.xz && tar xf zig.tar.xz
ENV PATH=$PATH:/zig-x86_64-linux-0.14.1
RUN apk add gcc g++ make gfortran blas lapack
RUN python | curl -L https://bootstrap.pypa.io/pip/3.7/get-pip.py
RUN pip install numpy==1.21.6
ADD . .
RUN --mount=type=cache,target=.zig-cache --mount=type=cache,target=~/.cache/zig zig build test -Dstrip