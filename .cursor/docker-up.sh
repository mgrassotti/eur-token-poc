#!/usr/bin/env bash
# Shared helpers: start the Docker daemon inside the Cloud Agent VM and expose
# a readiness check for bitcoind. Sourced by install.sh and start.sh.
#
# The VM has no systemd, so dockerd is started by hand. Nested Docker also needs
# br_netfilter disabled for the bridge, otherwise same-network container traffic
# (e.g. electrs -> bitcoind, pythia -> postgres) is dropped by the host iptables
# FORWARD chain and every service times out.

start_dockerd() {
  if docker info >/dev/null 2>&1; then
    :
  else
    echo "  starting dockerd..."
    sudo nohup dockerd >/tmp/dockerd.log 2>&1 &
    for _ in $(seq 1 60); do
      docker info >/dev/null 2>&1 && break
      sleep 1
    done
  fi
  sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

  # Let same-bridge container traffic be switched at L2 instead of being sent
  # through the host's iptables FORWARD chain (where it is dropped in this VM).
  sudo modprobe br_netfilter 2>/dev/null || true
  sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
  sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true

  if ! docker info >/dev/null 2>&1; then
    echo "  ERROR: Docker daemon did not become ready" >&2
    return 1
  fi
  echo "  dockerd ready"
}

wait_for_bitcoind() {
  echo "  waiting for bitcoind regtest on :18443..."
  for _ in $(seq 1 90); do
    if curl -sf --user regtest:regtest \
        --data-binary '{"jsonrpc":"1.0","id":1,"method":"getblockchaininfo","params":[]}' \
        -H "content-type: application/json" http://127.0.0.1:18443/ >/dev/null 2>&1; then
      echo "  bitcoind ready"
      return 0
    fi
    sleep 1
  done
  echo "  ERROR: bitcoind did not become ready in time" >&2
  return 1
}

# When sourced, ensure the daemon is up so callers can use docker immediately.
start_dockerd
