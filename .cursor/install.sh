#!/usr/bin/env bash
# Idempotent bootstrap for the MAT PoC Cloud Agent environment.
# Prepares Ruby + gems + databases and bakes the regtest/DLC Docker images.
# Safe to re-run: every step checks for existing state before doing work.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

echo "== [1/7] System packages =="
if ! dpkg -s build-essential >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq --no-install-recommends \
    build-essential libssl-dev libyaml-dev libffi-dev zlib1g-dev libreadline-dev \
    libgmp-dev libvips pkg-config libncurses-dev libgdbm-dev libdb-dev uuid-dev \
    curl git docker.io docker-compose-v2 || true
fi

echo "== [2/7] Ruby toolchain (mise + Ruby from .ruby-version) =="
if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$PATH"
grep -q 'mise activate' "$HOME/.bashrc" 2>/dev/null || \
  echo 'eval "$('"$HOME"'/.local/bin/mise activate bash)"' >> "$HOME/.bashrc"
grep -q 'mise/shims' "$HOME/.profile" 2>/dev/null || \
  echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
mise use -g "ruby@$(cat .ruby-version)"
export PATH="$HOME/.local/share/mise/shims:$PATH"
gem install bundler --conservative >/dev/null 2>&1 || gem install bundler

echo "== [3/7] Git submodule for the Pythia oracle image =="
git submodule update --init vendor/pythia

echo "== [4/7] Ruby gems =="
bundle install

echo "== [5/7] Test database schema =="
RAILS_ENV=test bin/rails db:test:prepare

echo "== [6/7] Docker daemon + regtest image build =="
source .cursor/docker-up.sh
docker compose -f docker-compose.regtest.yml --profile dlc build

echo "== [7/7] Bring up regtest stack and seed the development database =="
docker compose -f docker-compose.regtest.yml --profile dlc up -d
wait_for_bitcoind
bin/rails db:prepare

echo "== install.sh complete =="
