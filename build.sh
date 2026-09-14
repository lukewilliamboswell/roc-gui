#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$repo_dir"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
    echo "This initial platform supports Linux x86_64 only." >&2
    exit 1
fi

cargo build --release --package roc-gui-host
mkdir -p platform/targets/x64glibc
cp target/release/libhost.a platform/targets/x64glibc/libhost.a
echo "Built platform/targets/x64glibc/libhost.a"

