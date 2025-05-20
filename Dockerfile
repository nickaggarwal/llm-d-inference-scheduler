# syntax=docker/dockerfile:1.4              # enable BuildKit features
#### Stage 1: build ####
FROM quay.io/projectquay/golang:1.24 AS builder

ARG TARGETOS
ARG TARGETARCH
WORKDIR /workspace

# 1. Install C/C++ toolchain (cached unless this line changes)
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y gcc-c++ libstdc++ libstdc++-devel clang && \
    dnf clean all

# 2. Download and index HuggingFace tokenizer library (cached by args)
RUN mkdir lib && \
    curl -fsSL \
      https://github.com/daulet/tokenizers/releases/download/v1.20.2/\
libtokenizers.${TARGETOS}-${TARGETARCH}.tar.gz | tar -xz -C lib && \
    ranlib lib/*.a

# 3. Cache Go modules
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# 4. Copy application source
COPY cmd/    cmd/
COPY pkg/    pkg/
COPY internal/ internal/

# 5. Build the binary
ENV CGO_ENABLED=1 \
    GOOS=${TARGETOS:-linux} \
    GOARCH=${TARGETARCH}
RUN go build \
    -o bin/epp \
    -ldflags="-extldflags '-L$(pwd)/lib'" \
    cmd/epp/main.go cmd/epp/health.go

#### Stage 2: runtime ####
FROM registry.access.redhat.com/ubi9/ubi:latest
WORKDIR /

# only the compiled binary
COPY --from=builder /workspace/bin/epp /app/epp

# non-root user
USER 65532:65532

# expose ports
EXPOSE 9002 9003 9090

ENTRYPOINT ["/app/epp"]