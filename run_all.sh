#!/usr/bin/env bash
# Runs the full admission matrix against already-running systems (see README.md).
# LLAGENTKEY: a LiteLLM key bound to an agent with max_budget_per_session (configs/litellm-agent.sh).
# Every test uses a fresh budget entity worth exactly $0.0045 (10 calls at true
# cost), unique prompts (--nonce), and the same fake upstream on :9400.
# Output: one JSON line per test on stdout.
set -u
PY=${PY:?python with httpx}; PAIPY=${PAIPY:?python with pydantic-ai-harness}; HERE=$(cd "$(dirname "$0")" && pwd)
INF046=${INF046:?venv with inferrail 0.4.6}; INF047=${INF047:?venv with inferrail 0.4.7}
run() { sys=$1; scope=$2; test=$3; shift 3; out=$("$PY" "$HERE/burst.py" --nonce "$@"); echo "{\"system\":\"$sys\",\"scope\":\"$scope\",\"test\":\"$test\",\"result\":$out}"; }
matrix() { # $1 system  $2 scope  $3 function that prints fresh per-test args
  sys=$1; scope=$2; fresh=$3
  a=$($fresh b); run "$sys" "$scope" burst30 $a --n 30; run "$sys" "$scope" wave2 $a --n 5
  a=$($fresh s); run "$sys" "$scope" seq15 $a --n 15 --sequential
  a=$($fresh sb); run "$sys" "$scope" stream_burst30 $a --n 30 --stream; run "$sys" "$scope" stream_wave2 $a --n 5 --stream
  a=$($fresh ss); run "$sys" "$scope" stream_seq15 $a --n 15 --sequential --stream
}
TAG=$(date +%s)
# Inferrail: per-work_id budget created with the CLI before each run.
inf046() { id=w$TAG$1; (cd "$INF046_DIR" && "$INF046/bin/inferrail" budget set --db ./budgets.db --scope work_id --scope-value $id --window per_work --mode block --limit-usd 0.0045 >/dev/null); echo "--url http://127.0.0.1:8211/v1/chat/completions --header X-Inferrail-Attribute-Work-Id:$id"; }
inf047() { id=w$TAG$1; (cd "$INF047_DIR" && "$INF047/bin/inferrail" budget set --db ./budgets.db --scope work_id --scope-value $id --window per_work --mode block --limit-usd 0.0045 >/dev/null); echo "--url http://127.0.0.1:8212/v1/chat/completions --header X-Inferrail-Attribute-Work-Id:$id"; }
# Inferrail 0.4.7, no pre-registration: fresh work_id per test, budget declared by header only.
infdecl() { echo "--url http://127.0.0.1:8212/v1/chat/completions --header X-Inferrail-Attribute-Work-Id:d$TAG$1 --header X-Inferrail-Budget-Usd:0.0045"; }
LM="Authorization: Bearer sk-bench-master"; CT="Content-Type: application/json"
llkey() { k=$(curl -s -X POST localhost:4000/key/generate -H "$LM" -H "$CT" -d '{"max_budget":0.0045,"models":["gpt-4o-mini"]}' | "$PY" -c "import sys,json;print(json.load(sys.stdin)['key'])"); echo "--url http://127.0.0.1:4000/v1/chat/completions --key $k"; }
LLPLAIN=$(curl -s -X POST localhost:4000/key/generate -H "$LM" -H "$CT" -d '{"models":["gpt-4o-mini"]}' | "$PY" -c "import sys,json;print(json.load(sys.stdin)['key'])")
llcust() { id=c$TAG$1; curl -s -X POST localhost:4000/customer/new -H "$LM" -H "$CT" -d "{\"user_id\":\"$id\",\"max_budget\":0.0045}" >/dev/null; echo "--url http://127.0.0.1:4000/v1/chat/completions --key $LLPLAIN --extra {\"user\":\"$id\"}"; }
lldefault() { echo "--url http://127.0.0.1:4000/v1/chat/completions --key $LLPLAIN --extra {\"user\":\"d$TAG$1\"}"; }
llsession() { echo "--url http://127.0.0.1:4000/v1/chat/completions --key $LLAGENTKEY --extra {\"metadata\":{\"session_id\":\"s$TAG$1\"}}"; }
OM="Authorization: Bearer sk-otari-bench"
otkey() { bid=$(curl -s -X POST localhost:8300/api/v1/budgets -H "$OM" -H "$CT" -d '{"max_budget":0.0045}' | "$PY" -c "import sys,json;d=json.load(sys.stdin);print(d.get('budget_id') or d.get('id'))"); kj=$(curl -s -X POST localhost:8300/api/v1/keys -H "$OM" -H "$CT" -d '{"key_name":"bench"}'); kid=$(echo "$kj" | "$PY" -c "import sys,json;print(json.load(sys.stdin)['id'])"); curl -s -X POST localhost:8300/api/v1/scoped-budgets -H "$OM" -H "$CT" -d "{\"scope_type\":\"api_token\",\"scope_id\":\"$kid\",\"budget_id\":\"$bid\"}" >/dev/null; k=$(echo "$kj" | "$PY" -c "import sys,json;print(json.load(sys.stdin)['key'])"); echo "--url http://127.0.0.1:8300/api/v1/chat/completions --key $k --model openai:gpt-4o-mini"; }
rp() { echo "--url http://127.0.0.1:4100/v1/chat/completions --key bench --header X-RelayPlane-Bypass:true --header X-RelayPlane-Run-Cap-Usd:0.0045 --header X-RelayPlane-Run:r$TAG$1"; }
matrix inferrail-0.4.6 per_work_id inf046
matrix inferrail-0.4.7 per_work_id inf047
matrix inferrail-0.4.7 declared_header_unseen_id infdecl
matrix litellm key_max_budget llkey
matrix litellm customer_precreated llcust
matrix litellm customer_default_unseen_id lldefault
matrix litellm agent_session llsession
matrix otari api_token_scoped otkey
matrix relayplane per_run_header rp
for m in "" "--sequential"; do n=30; [ -n "$m" ] && n=15; out=$("$PAIPY" "$HERE/pydantic_ai_spendlimits.py" --n $n $m 2>/dev/null | tail -1); echo "{\"system\":\"pydantic-ai\",\"scope\":\"SpendLimits_total_partition\",\"test\":\"$( [ -n "$m" ] && echo seq15 || echo burst30 )\",\"result\":$out}"; done
