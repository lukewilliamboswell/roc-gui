#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$repo_dir"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "This initial platform supports Linux x86_64 only." >&2
    exit 1
fi

host_commit="$(git rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$host_commit" ]]; then
    host_commit="unavailable"
fi
if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    host_dirty="1"
else
    host_dirty="0"
fi

ROC_GUI_HOST_COMMIT="$host_commit" ROC_GUI_HOST_DIRTY="$host_dirty" \
    cargo build --release --package roc-gui-host
mkdir -p platform/targets/x64glibc
cp target/release/libhost.a platform/targets/x64glibc/libhost.a
echo "Built platform/targets/x64glibc/libhost.a"
