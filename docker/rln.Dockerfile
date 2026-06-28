# RGB Lightning Node image for the regtest demo.
# Builds the binary from the vendored submodule (vendor/rgb-lightning-node, with
# its nested rust-lightning submodule). Uses a debug build: much faster than the
# upstream release Dockerfile, which is what we want for a local regtest stack.
#
# Build context must be the repo root so the vendored source is available.
FROM rust:1.95-slim-trixie AS builder
WORKDIR /src
COPY vendor/rgb-lightning-node/ .
RUN cargo build

FROM debian:trixie-slim
COPY --from=builder /src/target/debug/rgb-lightning-node /usr/bin/rgb-lightning-node
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openssl \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENTRYPOINT ["/usr/bin/rgb-lightning-node"]
