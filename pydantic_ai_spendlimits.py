"""Same workload as burst.py, but in-process with Pydantic AI SpendLimits.

N concurrent agent runs share one budget partition (scope='job-1',
window='total', $0.0045 = 10 calls at true cost) against the fake upstream.
usage: pydantic_ai_spendlimits.py [--n 30] [--sequential]
"""
from __future__ import annotations

import argparse
import asyncio
import collections
import json
from decimal import Decimal

import httpx
from pydantic_ai import Agent
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.settings import ModelSettings
from pydantic_ai_harness import SpendLimits
from pydantic_ai_harness.spend import Budget

ap = argparse.ArgumentParser()
ap.add_argument("--n", type=int, default=30)
ap.add_argument("--sequential", action="store_true")
ap.add_argument("--upstream", default="http://127.0.0.1:9400")
a = ap.parse_args()

model = OpenAIChatModel("gpt-4o-mini", provider=OpenAIProvider(base_url=f"{a.upstream}/v1", api_key="bench"))
limits = SpendLimits(budgets=[Budget(usd=Decimal("0.0045"), window="total", scope=lambda ctx: "job-1", name="job")])
agent = Agent(model, capabilities=[limits], model_settings=ModelSettings(max_tokens=500))
PROMPT = "x " * 1500


async def one() -> str:
    try:
        await agent.run(PROMPT)
        return "ok"
    except Exception as e:  # noqa: BLE001
        return type(e).__name__


async def main() -> None:
    async with httpx.AsyncClient() as c:
        await c.post(f"{a.upstream}/reset")
    if a.sequential:
        outcomes = [await one() for _ in range(a.n)]
    else:
        outcomes = await asyncio.gather(*(one() for _ in range(a.n)))
    async with httpx.AsyncClient() as c:
        s = (await c.get(f"{a.upstream}/stats")).json()
    status = await limits.status(scope="job-1")
    print(json.dumps({"mode": "sequential" if a.sequential else "burst", "sent": a.n,
                      "outcomes": dict(collections.Counter(outcomes)),
                      "upstream_calls": s["calls"], "upstream_max_in_flight": s["max_in_flight"],
                      "upstream_cost_usd": round(s["calls"] * 0.00045, 6),
                      "spendlimits_recorded_usd": str(status[0].spent.usd) if status else None}))


asyncio.run(main())
