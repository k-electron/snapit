#!/usr/bin/env bash
# Checks that snapit's network calls are all in one file (`GitHubReleaseEndpoint.swift`): Check for
# Updates' request to GitHub's latest-release endpoint and, when the user then chooses Update and
# Relaunch, the download of that release's disk image and its `.sha256`. It is a static check, a tripwire for
# the ways code gets online; flow 56 of the scripted run adds the runtime check (no internet
# socket in either process).
#
#   1. Code that opens a connection or fetches a remote resource (URLSession, URLRequest,
#      NWConnection, sockets to an address, AsyncImage, HTML in an attributed string, a web view,
#      a shell tool such as curl, ...) may exist in exactly one file. The check fails when that
#      file stops matching, so a pattern that finds nothing cannot pass.
#   2. An `http(s)://` address in Swift code may appear only in the files that name GitHub's.
#   3. Config (Info.plist, entitlements, the project's build settings) asks for no network
#      entitlement and no App Transport Security exception.
#   4. The engine uses no network, and neither does anything it depends on: the crates in
#      Cargo.lock and the Swift packages in Package.resolved are allowlists. A new dependency
#      fails here until someone has read it and added it below.
#
# WebKit: a web view can load anything, so `import WebKit` fails unless the file is listed in
# WEBKIT_ALLOWED. The list is empty: the User Guide is a bundled Markdown file drawn natively
# (snapit-editor/UserGuide/), so no web view is needed.
#
#   scripts/check-network.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALLOWED="snapit/Updates/GitHubReleaseEndpoint.swift"
WEBKIT_ALLOWED=()
HTTP_LITERAL_ALLOWED=$'Shared/Updates/UpdateAnswer.swift\nsnapit/Updates/ReleaseEndpoint.swift'
ALLOWED_CRATES="adler2 bitflags cfg-if crc32fast fdeflate flate2 libc miniz_oxide png simd-adler32 snapit-engine zlib-rs"
ALLOWED_PACKAGES="keyboardshortcuts"

SWIFT_PATTERN='URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWPathMonitor|NWBrowser|import Network|CFNetwork|CFHTTP|CFSocket|CFStream|AF_INET|PF_INET|sockaddr_in|getaddrinfo|gethostbyname|SCNetworkReachability|NSNetService|NetService|AsyncImage|documentType|resourceBytes|\)\.lines\b|[uU]rl\.lines\b'
SHELL_PATTERN='"(curl|nc|ncat|wget|ssh|scp|sftp|ftp|telnet|socat)"|/usr/bin/(curl|nc|ssh|scp|sftp|ftp|telnet)|/usr/bin/env'
WEBKIT_PATTERN='import WebKit|WKWebView|WebView'
ENGINE_PATTERN='std::net|std::os::unix::net|TcpStream|TcpListener|UdpSocket|reqwest|ureq|hyper|curl|tokio|isahc|attohttpc|socket2|libc::(socket|connect|bind|listen|accept|send|sendto|recv|recvfrom|getaddrinfo|gethostbyname|setsockopt)|AF_INET|sockaddr_in'
SOURCES=(snapit snapit-editor Shared Config)
INCLUDES=(--include='*.swift' --include='*.m' --include='*.mm' --include='*.c' --include='*.h' --include='*.plist' --include='*.entitlements')

status=0
fail() { echo "error: $1" >&2; status=1; }

found="$({ grep -rlE "$SWIFT_PATTERN|$SHELL_PATTERN" "${SOURCES[@]}" "${INCLUDES[@]}" 2>/dev/null || true; } | sort)"
if [[ "$found" != "$ALLOWED" ]]; then
  fail "network use is allowed in $ALLOWED only. Found in: ${found:-<no file>}"
fi

webkit="$({ grep -rlE "$WEBKIT_PATTERN" "${SOURCES[@]}" "${INCLUDES[@]}" 2>/dev/null || true; } | sort)"
for file in $webkit; do
  case " ${WEBKIT_ALLOWED[*]:-} " in
    *" $file "*) ;;
    *) fail "$file uses WebKit, which can load anything; list it in WEBKIT_ALLOWED after review" ;;
  esac
done

literals="$({ grep -rlE 'https?://' "${SOURCES[@]}" --include='*.swift' --include='*.m' --include='*.mm' --include='*.c' 2>/dev/null || true; } | sort)"
if [[ "$literals" != "$HTTP_LITERAL_ALLOWED" ]]; then
  fail "an http(s):// address is allowed only in: $(echo "$HTTP_LITERAL_ALLOWED" | tr '\n' ' '). Found in: ${literals:-<no file>}"
fi

if grep -nE 'NSAppTransportSecurity|NSAllowsArbitraryLoads|com\.apple\.security\.network' snapit.xcodeproj/project.pbxproj >&2 \
  || grep -rnE 'NSAppTransportSecurity|NSAllowsArbitraryLoads|com\.apple\.security\.network' "${SOURCES[@]}" \
    --include='*.plist' --include='*.entitlements' >&2; then
  fail "a network entitlement or an App Transport Security setting is configured"
fi

if grep -rnE "$ENGINE_PATTERN" engine/src engine/Cargo.toml Cargo.toml >&2 2>/dev/null; then
  fail "the engine must not use the network"
fi

crates="$(sed -n 's/^name = "\(.*\)"/\1/p' Cargo.lock | sort -u | tr '\n' ' ')"
for crate in $crates; do
  case " $ALLOWED_CRATES " in *" $crate "*) ;; *) fail "Cargo.lock has a crate that is not on the reviewed list: $crate" ;; esac
done

packages="$(sed -n 's/^ *"identity" *: *"\(.*\)".*/\1/p' snapit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | sort -u | tr '\n' ' ')"
for package in $packages; do
  case " $ALLOWED_PACKAGES " in *" $package "*) ;; *) fail "Package.resolved has a package that is not on the reviewed list: $package" ;; esac
done

if ((status == 0)); then echo "ok"; fi
exit "$status"
