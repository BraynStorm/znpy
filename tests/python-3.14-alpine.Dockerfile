FROM python:3.14.0rc2-alpine
RUN apk add zig
RUN pip install numpy
ADD . .
RUN --mount=type=cache,target=.zig-cache --mount=type=cache,target=~/.cache/zig zig build test -Dstrip