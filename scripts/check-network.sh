#!/usr/bin/env bash
# Checks that snapit's one network call is the only one: Check for Updates' request to GitHub's
# latest-release endpoint. Code that opens a connection (URLSession, URLRequest, NWConnection,
# sockets to an address, ...) may exist in exactly one file. Nothing in the Rust engine or its
# dependencies may use the network either. The check also fails when that one file stops
# matching, so a pattern that no longer finds anything cannot pass.
#
#   scripts/check-network.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALLOWED="snapit/Updates/GitHubReleaseEndpoint.swift"
SWIFT_PATTERN='URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWPathMonitor|NWBrowser|import Network|CFNetwork|CFHTTP|CFSocket|CFStream|AF_INET|SCNetworkReachability|NSNetService|NetService'
ENGINE_PATTERN='std::net|TcpStream|TcpListener|UdpSocket|reqwest|ureq|hyper|curl|tokio|isahc|attohttpc|socket2'

status=0

found="$(grep -rlE "$SWIFT_PATTERN" snapit snapit-editor Shared Config --include='*.swift' --include='*.plist' --include='*.entitlements' 2>/dev/null | sort || true)"
if [[ "$found" != "$ALLOWED" ]]; then
  echo "error: network use is allowed in $ALLOWED only. Found in:" >&2
  echo "${found:-<no file>}" >&2
  status=1
fi

if grep -rnE "$ENGINE_PATTERN" engine/src engine/Cargo.toml Cargo.toml >&2 2>/dev/null; then
  echo "error: the engine must not use the network" >&2
  status=1
fi
# Dependencies the engine and the app resolve: none may be a networking library.
if grep -nE '^name = "(reqwest|ureq|hyper|curl|tokio|isahc|attohttpc|socket2|openssl|rustls|native-tls)"' Cargo.lock >&2 2>/dev/null; then
  echo "error: a networking crate is in Cargo.lock" >&2
  status=1
fi

if ((status == 0)); then echo "ok"; fi
exit "$status"
