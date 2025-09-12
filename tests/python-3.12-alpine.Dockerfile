FROM python:3.12-alpine
RUN apk add curl
RUN curl https://ziglang.org/download/0.15.1/zig-x86_64-linux-0.15.1.tar.xz -o zig.tar.xz && tar xf zig.tar.xz
ENV PATH=$PATH:/zig-x86_64-linux-0.15.1
RUN pip install numpy==2.3.2
WORKDIR /znpy
ADD . .
RUN --mount=type=cache,target=/znpy/.zig-cache --mount=type=cache,target=~/.cache/zig zig build test