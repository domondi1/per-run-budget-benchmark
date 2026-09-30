"""Fire N identical chat completions at once against a gateway; report
admitted vs refused, and what the upstream actually served.

usage: burst.py --url URL --n 30 [--header K:V ...] [--key KEY] [--model M] [--stream]
"""
from __future__ import annotations

import argparse
import asyncio
import collections
import json

import httpx

PROMPT = "x " * 1500  # 3000 chars; ~1000 tokens by a 3-chars/token estimate

ap = argparse.ArgumentParser()
ap.add_argument("--url", required=True)
ap.add_argument("--n", type=int, default=30)
ap.add_argument("--header", action="append", default=[])
ap.add_argument("--key", default="unused")
ap.add_argument("--model", default="gpt-4o-mini")
ap.add_argument("--max-tokens", type=int, default=500)
ap.add_argument("--stream", action="store_true")
ap.add_argument("--nonce", action="store_true", help="append a unique suffix to each prompt (defeats response caches)")
ap.add_argument("--sequential", action="store_true", help="send one at a time instead of all at once")
ap.add_argument("--upstream", default="http://127.0.0.1:9400")
ap.add_argument("--extra", default="{}", help="extra JSON merged into the body")
a = ap.parse_args()


_counter = iter(range(10**9))


async def one(client: httpx.AsyncClient) -> int:
    content = PROMPT + (f" #{next(_counter)}-{id(client)}" if a.nonce else "")
    body = {"model": a.model, "max_tokens": a.max_tokens, "stream": a.stream,
            "messages": [{"role": "user", "content": content}], **json.loads(a.extra)}
    try:
        r = await client.post(a.url, json=body)
        if a.stream:
            await r.aread()
        return r.status_code
    except Exception as e:  # noqa: BLE001
        return -1


async def main() -> None:
    headers = {"Authorization": f"Bearer {a.key}"}
    for h in a.header:
        k, v = h.split(":", 1)
        headers[k.strip()] = v.strip()
    async with httpx.AsyncClient(headers=headers, timeout=120) as up:
        await up.post(f"{a.upstream}/reset")
    async with httpx.AsyncClient(headers=headers, timeout=120,
                                 limits=httpx.Limits(max_connections=a.n)) as client:
        if a.sequential:
            codes = [await one(client) for _ in range(a.n)]
        else:
            codes = await asyncio.gather(*(one(client) for _ in range(a.n)))
    async with httpx.AsyncClient(timeout=30) as up:
        s = (await up.get(f"{a.upstream}/stats")).json()
    print(json.dumps({"nonce": a.nonce, "mode": "sequential" if a.sequential else "burst", "stream": a.stream, "sent": a.n, "status_codes": dict(collections.Counter(codes)),
                      "upstream_calls": s["calls"], "upstream_max_in_flight": s["max_in_flight"],
                      "upstream_cost_usd": round(s["calls"] * 0.00045, 6)}))


asyncio.run(main())
