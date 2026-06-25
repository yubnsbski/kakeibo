#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"

cd "$repo_root"
npm run verify

cd "$repo_root/frontend"
npm run build

cd "$repo_root/backend"
python3 -m unittest tests.test_calculation
