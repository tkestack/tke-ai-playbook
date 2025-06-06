FROM ghcr.io/flant/shell-operator:latest
COPY --from=ghcr.io/astral-sh/uv:0.6.17 /uv /uvx /bin/
RUN apk update && apk add coreutils

ADD hooks /hooks