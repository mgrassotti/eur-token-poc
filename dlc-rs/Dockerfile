# Rust DLC node sidecar (rust-dlc). Built for linux/amd64 (compose pins platform).
# The crypto stack (dlc/dlc-trie/dlc-messages + secp256k1-zkp) compiles from source;
# we use a dependency-only pre-build layer so source edits don't refetch/recompile
# the (slow) DLC + libsecp256k1 dependencies.
FROM rust:1-bookworm AS build

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates pkg-config \
  && rm -rf /var/lib/apt/lists/*

# 1) Dependency cache layer: build a stub against the real Cargo.toml so the git
#    DLC crates + libsecp256k1 are fetched and compiled once and cached.
COPY Cargo.toml ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs \
  && cargo build --release \
  && rm -rf src

# 2) Real sources.
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/target/release/dlc-node /usr/local/bin/dlc-node

ENV PORT=8090
EXPOSE 8090
CMD ["dlc-node"]
