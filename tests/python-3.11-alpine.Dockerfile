FROM python:3.11-alpine
RUN apk add zig
RUN pip install numpy==2.2.6
ADD . .
RUN --mount=type=cache,target=.zig-cache --mount=type=cache,target=~/.cache/zig zig build test -Dstrip