#!/bin/bash
# Fails if the app gains a way to reach the network, the microphone or the camera, or any
# entitlement beyond the sandbox, user-chosen files and app-scoped bookmarks.
# These back the privacy promise in the README and SECURITY.md.
set -euo pipefail
cd "$(dirname "$0")/.."

ENT=Resources/Recap.entitlements
fail=0

if grep -rnE "URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|import Network|WKWebView|CFSocket|CFStream|SocketPort|NSStream|getaddrinfo|AVCaptureDevice|AVAudioEngine|inputNode|SFSpeechRecognizer" Sources/; then
    echo "A networking, microphone or camera API appears in Sources/. Recap promises none of these." >&2
    fail=1
fi

if [ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$ENT" 2>/dev/null)" != "true" ]; then
    echo "The App Sandbox entitlement is missing or not true." >&2
    fail=1
fi

# Exactly these three keys, all true. Anything else (network, microphone, camera, wider file access) fails.
ALLOWED="com.apple.security.app-sandbox com.apple.security.files.bookmarks.app-scope com.apple.security.files.user-selected.read-write"
FOUND=$(plutil -convert json -o - "$ENT" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(sorted(k for k,v in d.items() if v is True))); sys.exit(0 if all(v is True for v in d.values()) else 3)') || {
    echo "Every entitlement must be a plain true value." >&2; fail=1; }
if [ "$FOUND" != "$ALLOWED" ]; then
    echo "Entitlements must be exactly: $ALLOWED" >&2
    echo "Found: $FOUND" >&2
    fail=1
fi

[ $fail -eq 0 ] && echo "No-network check passed"
exit $fail
