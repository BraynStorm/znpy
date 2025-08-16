#/bin/sh
set -ex
docker build . -f tests/python-3.7-alpine.Dockerfile -t znpy
docker build . -f tests/python-3.8-alpine.Dockerfile -t znpy
docker build . -f tests/python-3.9-alpine.Dockerfile -t znpy
docker build . -f tests/python-3.10-alpine.Dockerfile -t znpy
docker build . -f tests/python-3.11-alpine.Dockerfile -t znpy
docker build . -f tests/python-3.12-alpine.Dockerfile -t znpy
docker build . -f tests/python-3.13-alpine.Dockerfile -t znpy
# docker build . -f tests/python-3.14-alpine.Dockerfile -t test
docker image rm znpy
# docker image prune -f