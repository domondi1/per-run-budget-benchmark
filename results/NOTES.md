# Run notes, 20260930T011822Z

- `raw-20260930T011822Z.jsonl`: the full matrix (56 tests).
- `raw-20260930T011822Z-litellm-agent-rerun.jsonl`: the LiteLLM `agent_session` row,
  rerun. In the full run the agent-setup script failed (an agent with the
  same name already existed from a manual check), so the key it used was
  not bound to an agent and that row measured an unbudgeted key. The
  script now uses a unique agent name and verifies the binding
  (`configs/litellm-agent.sh`). The rerun file supersedes those 6 rows;
  `summary-20260930T011822Z.md` is built from both files, later file winning.
- Sequential results for LiteLLM's default-customer and agent-session
  budgets varied by 1–3 calls between runs on the same versions (for
  example agent_session seq15: 10 in an earlier run, 11 here). The burst
  results were identical across runs.
