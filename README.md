# What happens when 30 model calls hit one budget at once

A reproducible test of per-run dollar budgets under concurrency. One job's
budget is shared by many model calls; does each system refuse calls
**before** they reach the provider, so total spend stays within the
budget? Tested with concurrent calls, sequential calls, and streams where
the client didn't ask for usage.

This measures admission correctness only. It does not measure latency,
provider breadth, routing, UI, observability, support, or behaviour at
production scale, and no real provider is used.

## Workload (identical for every system)

- **Upstream:** [`fake_upstream.py`](fake_upstream.py), an
  OpenAI-compatible server on `:9400`. Every call reports exactly 1000
  prompt and 500 completion tokens after a fixed 1.0 s delay. At
  gpt-4o-mini list price ($0.15 / $0.60 per million tokens) that is
  **$0.00045 per call**. The delay keeps every call of a burst in flight
  at once. The upstream counts the calls it actually served; that count is
  the ground truth for money spent.
- **Request:** model `gpt-4o-mini`, one user message of 3000 characters
  plus a unique suffix (defeats response caches), `max_tokens: 500`.
- **Budget:** a fresh budget per test worth **$0.0045**, exactly 10 calls
  at true cost.
- **Tests** ([`burst.py`](burst.py), [`run_all.sh`](run_all.sh)):
  - `burst30`: 30 calls at once; `wave2`: 5 more on the same budget after.
  - `seq15`: 15 calls one at a time on a new budget.
  - `stream_*`: the same with `stream: true` and no
    `stream_options.include_usage` from the client.
- **Pydantic AI** is a library, not a gateway:
  [`pydantic_ai_spendlimits.py`](pydantic_ai_spendlimits.py) runs 30
  concurrent `agent.run` calls sharing one `SpendLimits` budget, then 15
  sequential ones. Streaming wasn't tested for it.
- **Correct outcome:** at most 10 calls reach the upstream per budget.
  Fewer is conservative; more is spend past the budget.

## Systems and exact versions

| System | Version / artifact | Budget scope tested | Config |
|---|---|---|---|
| Inferrail | PyPI `inferrail==0.4.7` | (a) per-run budget declared in a request header, new run id each test; (b) per-run budget created with the CLI | [`inferrail-bench.yaml`](inferrail-bench.yaml) |
| Inferrail (previous release) | PyPI `inferrail==0.4.6` | per-run budget created with the CLI | same |
| LiteLLM proxy | 1.103.0, `ghcr.io/berriai/litellm-database@sha256:f4f114b1996c5923c4d62a7bbdcecb2ccf9df17bdebce76050f609be97f75f5c` + `postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea` | (a) virtual-key `max_budget`; (b) pre-created customer `max_budget` (request `user`); (c) default budget for an unseen customer id (`max_end_user_budget_id`); (d) agent `max_budget_per_session` (request `metadata.session_id`) | [`configs/litellm-*`](configs/) |
| otari | 0.4.0, `mzdotai/otari@sha256:8ca32c6c43b6f6c8f38df9dda6604ecdbd6e34f60148386e4ee83fe3f3756ad0`, image source revision `f36010557d576c979afaaa1ac6f0f732cedf7dd5` (built 2026-09-28; the `v0.4.0` git tag, `b39c5f0`, has an older budget model — `/scoped-budgets` comes from this newer source), in-container SQLite | budget scoped to one API token | [`configs/otari-env.sh`](configs/otari-env.sh) |
| RelayPlane | `@relayplane/proxy` 1.9.69 (and 1.9.70 rerun), Node v24.14.0 | per-run cap header `X-RelayPlane-Run-Cap-Usd` + `X-RelayPlane-Run` | [`configs/relayplane-*`](configs/) |
| Pydantic AI | `pydantic-ai-slim` 2.51.0, `pydantic-ai-harness` 0.36.0, `genai-prices` 0.1.9 | `SpendLimits` `Budget(window='total', scope='job-1')` | [`pydantic_ai_spendlimits.py`](pydantic_ai_spendlimits.py) |

### Setup details per budget scope

- **LiteLLM, all scopes:** no Redis configured; `proxy_batch_write_at`
  and `litellm.default_redis_ttl` not set (defaults). Postgres 16 for
  spend.
- **LiteLLM virtual key:** a new key with `max_budget: 0.0045` per test.
- **LiteLLM customer, pre-created:** `/customer/new` with `max_budget:
  0.0045` for a new customer id **before** each test; the setup asserts
  the returned budget. Requests carry that id in `user`.
- **LiteLLM default budget, unseen customer id:** the id does **not**
  exist before the test; `max_end_user_budget_id: bench-run-default`
  attaches the default `$0.0045` budget. Requests carry the new id in
  `user`.
- **LiteLLM agent session:** an agent with `max_budget_per_session:
  0.0045` and a key bound to it (`configs/litellm-agent.sh` verifies the
  binding). Every request in a test carries the same
  `metadata.session_id` (one of the two documented ways to identify a
  session; the other is the `x-litellm-trace-id` header); each test uses
  a new session id.
- **otari:** a budget, a key and a scoped budget (`scope_type:
  api_token`) per test; the setup checks each returns 2xx and that the
  scoped budget references that key and budget. This emulates a job
  budget through token lifecycle: a pre-created, API-token-scoped shared
  budget with one fresh token per simulated job (not a request-level or
  job-id scope).
- Since 2026-10-01 every setup step fails closed: a failed or unexpected
  setup response stops the run instead of measuring an unbudgeted
  request.

Host: Linux 6.8 x86_64, 2 vCPU, 7 GB RAM, Docker 29.3.0 (host
networking), Python 3.12.1, httpx 0.28.1.

Not tested (no account available): hosted gateways such as Cloudflare AI
Gateway, Vercel AI Gateway and OpenRouter, and provider-native limits.

## Results

Calls that reached the upstream (budget = 10 calls). Run 2026-09-30;
raw lines in [`results/`](results/), notes in
[`results/NOTES.md`](results/NOTES.md).

| System | Budget scope | Created before the run? | External database | Setup to protect one run | 30 at once (+5 more) | 15 one at a time | Streams, no usage requested: 30 at once (+5) / 15 one at a time |
|---|---|---|---|---|---|---|---|
| Inferrail 0.4.7 | per run, header | no | none (SQLite file) | 2 request headers | 9 (+0) | 9 | 9 (+0) / 9 |
| Inferrail 0.4.7 | per run, CLI | yes | none (SQLite file) | 1 CLI call per run | 9 (+0) | 9 | 9 (+0) / 9 |
| Inferrail 0.4.6 (previous release) | per run, CLI | yes | none (SQLite file) | 1 CLI call per run | 30 (+0) | 9 | 30 (+5) / 15 |
| LiteLLM 1.103.0 | virtual key | yes | Postgres | 1 API call per key | 9 (+1) | 10 | 9 (+1) / 10 |
| LiteLLM 1.103.0 | customer, pre-created | yes | Postgres | 1 API call per customer | 9 (+1) | 10 | 9 (+1) / 10 |
| LiteLLM 1.103.0 | default budget, unseen customer id | no (default created once) | Postgres | none per run | 30 (+5) | 10 | 30 (+5) / 10 |
| LiteLLM 1.103.0 | agent session | no (agent + key created once) | Postgres | none per run | 30 (+0) | 11 | 30 (+0) / 10 |
| otari 0.4.0 | API token (pre-created; one fresh token per simulated job) | yes | none (SQLite in its container) | 3 API calls per token | 10 (+0) | 10 | 10 (+0) / 10 |
| RelayPlane 1.9.69 | per run, header | no | none | 2 request headers | 30 (+0) | 10 | 30 (+0) / 10 |
| RelayPlane 1.9.70 (rerun 2026-10-03) | per run, header | no | none | 2 request headers | 10 (+0) | 10 | 10 (+0) / 10 |
| Pydantic AI (harness 0.36.0) | `SpendLimits`, in-process | no | none | code | 30 | 10 | not tested |

**Update 2026-10-03:** RelayPlane's maintainer confirmed the 1.9.69 burst
result was a bug (admission checked recorded spend and only recorded cost when
the response came back) and fixed it in 1.9.70 by reserving each request's
estimated cost at admission ([issue #1](https://github.com/domondi1/per-run-budget-benchmark/issues/1)).
We reran the RelayPlane row on 1.9.70 with the same harness and config, no
changes: the cap now holds under the burst and under streams. Raw output:
`results/raw-20261003T000300Z-relayplane-1.9.70.jsonl`.

Machine summary of the same data: [`results/summary-*.md`](results/).

## Reproduce

1. Start the upstream: `uvicorn fake_upstream:app --port 9400`.
2. Start each system as in `configs/`:
   - LiteLLM: [`configs/litellm-run.sh`](configs/litellm-run.sh) (start
     with `litellm-config.yaml`, create the `bench-run-default` budget,
     restart with `litellm-config-default-enduser.yaml`), then
     `source configs/litellm-agent.sh` to get `LLAGENTKEY`.
   - otari: [`configs/otari-env.sh`](configs/otari-env.sh).
   - RelayPlane: [`configs/relayplane-run.sh`](configs/relayplane-run.sh).
   - Inferrail: two venvs (`pip install inferrail==0.4.6` and
     `inferrail==0.4.7`), each serving `inferrail-bench.yaml` from its own
     directory, on ports 8211 and 8212 (`inferrail serve --config
     inferrail-bench.yaml --port 8211`, with `BENCH_KEY` set to any
     value).
3. Run the matrix:

```bash
PY=<python with httpx> PAIPY=<python with pydantic-ai-harness> \
INF046=<0.4.6 venv> INF046_DIR=<its dir> INF047=<0.4.7 venv> INF047_DIR=<its dir> \
LLAGENTKEY=$LLAGENTKEY ./run_all.sh > results/raw-$(date -u +%Y%m%dT%H%M%SZ).jsonl
python summarize.py results/raw-*.jsonl
```

`rerun_one.sh "<matrix line from run_all.sh>"` reruns one system.

## Adjustments made for fairness

1. **LiteLLM:** the pip install (`litellm[proxy]`) also needs `prisma`
   and `prisma generate` before budgets are enforced, so the documented
   Docker image is used instead.
2. **LiteLLM default customer budget:** the float `max_end_user_budget`
   is documented as no longer enforced, so `max_end_user_budget_id` is
   used. After a restart the budget object is cached for up to 60 s
   (documented), so runs start with a warm cache.
3. **RelayPlane response cache:** identical prompts were served from its
   cache without reaching the upstream. Every prompt is unique, for every
   system.
4. **RelayPlane rate limiter:** its default 60 rpm per-model limiter
   queued and 429'd requests during bursts, mixing a rate limit into the
   budget result. The config raises `gpt-4o-mini` to 10000 rpm; no rate
   limit events occurred.
5. **RelayPlane routing** is bypassed (`X-RelayPlane-Bypass: true`) so
   every system serves the same model.

If a configuration here is unfair to a product, open an issue with the
correction and the test will be rerun.

## Disclosure

This benchmark is published by the Inferrail maintainers. Inferrail
0.4.6 is included because it let the burst through; 0.4.7 changed that.
