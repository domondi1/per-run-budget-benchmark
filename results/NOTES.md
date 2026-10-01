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

## 2026-10-01: review follow-ups (no rerun)

Two community reviews of the configuration
([LiteLLM discussion](https://github.com/BerriAI/litellm/discussions/43798),
[otari discussion](https://github.com/mozilla-ai/otari/discussions/1801))
led to these changes:

- otari: recorded the image's source revision (`f36010557d…`), since
  the `v0.4.0` tag predates the `/scoped-budgets` behaviour tested.
- otari and LiteLLM customer setup now fail closed (`curl
  --fail-with-body` plus checks that the created budget is the one
  attached). The 2026-09-30 run used the earlier setup, which didn't
  check responses. Its budgeted rows are consistent with setup having
  succeeded (otari admitted exactly 10 calls; the pre-created customer
  admitted 9, then 1), but that run doesn't prove it; the next run will.
- README: LiteLLM settings stated explicitly (no Redis; batch-write and
  Redis TTL at defaults), and how each LiteLLM scope was identified
  (customer pre-created or not; `metadata.session_id` for sessions).
