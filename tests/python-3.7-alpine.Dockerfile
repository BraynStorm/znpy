FROM python:3.7
RUN curl https://ziglang.org/download/0.15.1/zig-x86_64-linux-0.15.1.tar.xz -o zig.tar.xz && tar xf zig.tar.xz
ENV PATH=$PATH:/zig-x86_64-linux-0.15.1
RUN apt-get update
RUN apt-get install -y gcc g++ gfortran make libblas-dev
# RUN apk add gcc g++ make gfortran blas lapack
RUN python | curl -L https://bootstrap.pypa.io/pip/3.7/get-pip.py
RUN pip install numpy==1.21.6
WORKDIR /znpy
ADD . .
RUN --mount=type=cache,target=/znpy/.zig-cache --mount=type=cache,target=~/.cache/zig zig build test
# RUN ls /lib/python3/dist-packages && false