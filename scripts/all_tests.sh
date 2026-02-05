#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/run_pytests.sh"
"$ROOT_DIR/scripts/run_xsim_tests.sh"
