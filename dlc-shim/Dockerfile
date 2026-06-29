# cfd-js / cfd-dlc-js are native N-API addons fetched from GitHub. AtomicFinance
# publishes prebuilt binaries for node20/linux-x64 (napi-v3 / node-v115), so we
# install with --ignore-scripts (the git deps' default `install` script falls back
# to a full C++/CMake source build that hangs for hours under qemu emulation) and
# then fetch ONLY the prebuilt binaries explicitly via prebuild-install. git is
# required to clone the GitHub deps.
#
# Base must be trixie (GLIBC 2.41): the cfd-dlc-js prebuilt is linked against
# GLIBC_2.38, which Debian 12 (bookworm, GLIBC 2.36) does not provide.
FROM node:20-trixie-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package.json ./
# --ignore-scripts skips the native source-compile fallback for every package; the
# two native addons then pull their prebuilt binary directly. cfd-js loads via
# `bindings` from build/Release; cfd-dlc-js loads from wrap_js/build, so we mirror
# the copy its postinstall would normally perform.
RUN npm install --omit=dev --no-audit --no-fund --ignore-scripts \
  && ( cd node_modules/cfd-js && /app/node_modules/.bin/prebuild-install --runtime napi --verbose ) \
  && ( cd node_modules/cfd-dlc-js && /app/node_modules/.bin/prebuild-install --verbose \
       && mkdir -p wrap_js/build && cp -r build/* wrap_js/build/ )

COPY server.js ./

ENV PORT=8090
EXPOSE 8090

CMD ["node", "server.js"]
