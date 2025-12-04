# --------------------------------------------------------------------- base ---

FROM golang:1.24-alpine AS base

ARG BOT_VERSION=latest
ARG BOT_REPO=https://github.com/cruxstack/github-ops-app.git

WORKDIR /build

RUN apk add --no-cache git make zip

RUN if [ "${BOT_VERSION}" = "latest" ]; then \
      git clone --depth 1 ${BOT_REPO} .; \
    else \
      git clone --depth 1 --branch ${BOT_VERSION} ${BOT_REPO} .; \
    fi

RUN GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
    -ldflags="-s -w" \
    -o bootstrap \
    ./cmd/lambda

# ------------------------------------------------------------------ package ---

FROM alpine:latest AS package

COPY --from=base /build/bootstrap /opt/app/dist/bootstrap

RUN apk add zip \
    && cd /opt/app/dist \
    && zip -r /tmp/package.zip .
