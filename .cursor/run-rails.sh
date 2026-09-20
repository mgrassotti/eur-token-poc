#!/usr/bin/env bash
# Long-running Rails development server (shown as the 'rails' terminal).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
exec bin/rails server -b 0.0.0.0 -p 3000
