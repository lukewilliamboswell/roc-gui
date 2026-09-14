#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 /path/to/roc/source/checkout" >&2
    exit 1
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
roc_source_dir="$1"
glue_spec="$roc_source_dir/src/glue/src/RustGlue.roc"

if [[ ! -f "$glue_spec" ]]; then
    echo "Rust glue spec not found: $glue_spec" >&2
    exit 1
fi

cd "$repo_dir"
roc glue "$glue_spec" crates/host/src/ platform/main-glue.roc
cargo fmt --all
