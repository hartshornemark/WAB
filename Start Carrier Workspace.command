#!/bin/zsh

set -e

PROJECT_DIR="/Users/mahartshorne/Documents/Codex/2026-09-15/referenced-chatgpt-conversation-this-is-an/outputs/carrier-configuration"
CODEX_RUNTIME="/Users/mahartshorne/.cache/codex-runtimes/codex-primary-runtime/dependencies"

export PATH="$CODEX_RUNTIME/node/bin:$CODEX_RUNTIME/bin/fallback:$PATH"

cd "$PROJECT_DIR"

echo "Starting Carrier Configuration Workspace..."
echo "Open http://127.0.0.1:3054/carriers in your browser."
echo "Keep this window open. Press Control-C to stop the workspace."
echo

pnpm start --hostname 127.0.0.1 --port 3054
