#/bin/sh
set -ex
docker build . -f tests/python-3.7-alpine.Dockerfile  -t znpy-test:3.7
docker build . -f tests/python-3.8-alpine.Dockerfile  -t znpy-test:3.8
docker build . -f tests/python-3.9-alpine.Dockerfile  -t znpy-test:3.9
docker build . -f tests/python-3.10-alpine.Dockerfile -t znpy-test:3.10
docker build . -f tests/python-3.11-alpine.Dockerfile -t znpy-test:3.11
docker build . -f tests/python-3.12-alpine.Dockerfile -t znpy-test:3.12
docker build . -f tests/python-3.13-alpine.Dockerfile -t znpy-test:3.13
# docker build . -f tests/python-3.14-alpine.Dockerfile -t test
# docker image rm znpy-test:3.7
# docker image rm znpy-test:3.8
# docker image rm znpy-test:3.9
# docker image rm znpy-test:3.10
# docker image rm znpy-test:3.11
# docker image rm znpy-test:3.12
# docker image rm znpy-test:3.13
# docker image prune -f