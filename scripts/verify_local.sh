#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"

cd "$repo_root"
npm run verify

cd "$repo_root/frontend"
npm run build

cd "$repo_root"
PYTHONPATH=backend python3 -m unittest discover -s backend/tests -p 'test_*.py'
