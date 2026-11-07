# Builds github-ops-app (cruxstack/github-ops-app) for AWS Lambda
# (provided.al2023) and packages it as a zip.

# --------------------------------------------------------------------- base ---

FROM golang:1.27 AS base

# a git tag, branch, or commit of github-ops-app; "latest" builds the default
# branch, which can include breaking changes
ARG APP_VERSION=v1.0.0
ARG APP_REPO=https://github.com/cruxstack/github-ops-app.git
ARG GOARCH=arm64

ENV GOOS=linux
ENV GOARCH=${GOARCH}
ENV CGO_ENABLED=0
# let newer app versions download the go toolchain their go.mod requires
ENV GOTOOLCHAIN=auto

WORKDIR /opt/app

RUN git clone "$APP_REPO" . \
    && if [ "$APP_VERSION" != "latest" ]; then git checkout "$APP_VERSION"; fi
RUN go mod download
RUN go build -trimpath -tags lambda.norpc -ldflags "-s -w -X main.version=${APP_VERSION}" -o dist/bootstrap ./cmd/lambda

# ------------------------------------------------------------------ package ---

FROM alpine:3.24 AS package

COPY --from=base /opt/app/dist /opt/app/dist

RUN apk add --no-cache zip \
    && cd /opt/app/dist \
    && zip -X -r /tmp/package.zip .
