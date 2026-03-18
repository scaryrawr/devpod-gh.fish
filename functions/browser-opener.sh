#!/usr/bin/env bash
# Browser opener script for devpod
#
# This script is uploaded to the codespace and set as $BROWSER.
# It discovers the devpod browser service Unix socket and forwards
# URL open requests to the local machine via HTTP.

URL="$1"

if [ -z "$URL" ]; then
    echo "Usage: $0 <url>" >&2
    exit 1
fi

# Find all browser sockets (newest first to prefer active connections)
BROWSER_SOCKETS=$(find /tmp -maxdepth 1 -name "devpod-browser-*.sock" -type s -print0 2>/dev/null | xargs -0 -r ls -t 2>/dev/null)

if [ -z "$BROWSER_SOCKETS" ]; then
    exit 0
fi

# URL-encode the URL (use jq if available, otherwise pass as-is)
if command -v jq &>/dev/null; then
    ENCODED_URL=$(printf %s "$URL" | jq -sRr @uri)
else
    ENCODED_URL="$URL"
fi

# Try each socket until one succeeds
for BROWSER_SOCKET in $BROWSER_SOCKETS; do
    if curl -s --max-time 2 --unix-socket "$BROWSER_SOCKET" \
        -X POST "http://localhost/open?url=${ENCODED_URL}" \
        >/dev/null 2>&1; then
        exit 0
    fi
done

exit 0
