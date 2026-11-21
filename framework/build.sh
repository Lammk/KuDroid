#!/usr/bin/env bash
# Compile the framework through the shared build pipeline.
set -euo pipefail

FRAMEWORK_BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$FRAMEWORK_BUILD_DIR/build.py" "$@"
