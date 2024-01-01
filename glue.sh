#!/usr/bin/env bash

# run from root of repo with 

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

echo "Removing old glue files..."
rm -rf platform/glue

echo "Generating glue files..."
roc glue ../roc/crates/glue/src/RustGlue.roc platform/glue platform/main-glue.roc

echo "Complete"