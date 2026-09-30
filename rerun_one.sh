#!/usr/bin/env bash
# Re-run the run_all.sh matrix for ONE system (used when a system crashed mid-run).
# usage: rerun_one.sh <matrix-line-from-run_all.sh>   e.g. "matrix otari api_token_scoped otkey"
set -u
eval "$(sed -n '1,/^matrix inferrail-0.4.6/p' "$(dirname "$0")/run_all.sh" | sed '$d')"
eval "$1"
