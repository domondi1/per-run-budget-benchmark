# LiteLLM agent-session budget: an agent with max_budget_per_session, and a key bound to it.
set -e
# Requests then carry metadata.session_id; each new session id gets its own $0.0045.
LM="Authorization: Bearer sk-bench-master"; CT="Content-Type: application/json"
AID=$(curl -s -X POST localhost:4000/v1/agents -H "$LM" -H "$CT" -d '{"agent_name":"bench-agent-'"$(date +%s)"'",
  "agent_card_params":{"protocolVersion":"1.0","name":"bench","description":"bench","url":"http://127.0.0.1:9/",
  "version":"1.0.0","defaultInputModes":["text"],"defaultOutputModes":["text"],"capabilities":{},"skills":[]},
  "litellm_params":{"max_budget_per_session":0.0045}}' | python -c "import sys,json;print(json.load(sys.stdin)['agent_id'])")
export LLAGENTKEY=$(curl -s -X POST localhost:4000/key/generate -H "$LM" -H "$CT" \
  -d "{\"agent_id\":\"$AID\",\"models\":[\"gpt-4o-mini\"]}" | python -c "import sys,json;print(json.load(sys.stdin)['key'])")
KEY_AGENT=$(curl -s localhost:4000/key/info -H "Authorization: Bearer $LLAGENTKEY" | python -c "import sys,json;print(json.load(sys.stdin)['info'].get('agent_id') or '')")
[ "$KEY_AGENT" = "$AID" ] || { echo "LLAGENTKEY is not bound to agent $AID" >&2; return 1 2>/dev/null || exit 1; }
