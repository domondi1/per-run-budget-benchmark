"""Deterministic OpenAI-compatible upstream for admission benchmarks.

Every chat completion reports exactly 1000 prompt + 500 completion tokens
(gpt-4o-mini list price: $0.15/$0.60 per M -> $0.00045 per call) after a
fixed delay, so all calls in a burst are in flight together. Counts calls.
GET /stats, POST /reset.
"""
from __future__ import annotations

import asyncio
import json
import os

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

DELAY = float(os.environ.get("FAKE_DELAY_S", "1.0"))
USAGE = {"prompt_tokens": 1000, "completion_tokens": 500, "total_tokens": 1500}
app = FastAPI()
state = {"calls": 0, "stream_calls": 0, "in_flight": 0, "max_in_flight": 0, "paths": {},
         "inferrail_headers_seen": 0, "stream_options_seen": 0, "models_seen": {}}


@app.get("/stats")
async def stats() -> dict:
    return state


@app.post("/reset")
async def reset() -> dict:
    state.update(calls=0, stream_calls=0, in_flight=0, max_in_flight=0, paths={},
                 inferrail_headers_seen=0, stream_options_seen=0, models_seen={})
    return state


async def _complete(req: Request) -> Response:
    body = await req.json()
    state["calls"] += 1
    if any(k.lower().startswith("x-inferrail") for k in req.headers):
        state["inferrail_headers_seen"] += 1
    if body.get("stream_options"):
        state["stream_options_seen"] += 1
    state["models_seen"][body.get("model")] = state["models_seen"].get(body.get("model"), 0) + 1
    state["paths"][req.url.path] = state["paths"].get(req.url.path, 0) + 1
    state["in_flight"] += 1
    state["max_in_flight"] = max(state["max_in_flight"], state["in_flight"])
    try:
        await asyncio.sleep(DELAY)
    finally:
        state["in_flight"] -= 1
    model = body.get("model", "gpt-4o-mini")
    if not body.get("stream"):
        return JSONResponse({
            "id": "chatcmpl-bench", "object": "chat.completion", "created": 0, "model": model,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": "ok"},
                         "finish_reason": "stop"}],
            "usage": USAGE,
        })
    state["stream_calls"] += 1
    base = {"id": "chatcmpl-bench", "object": "chat.completion.chunk", "created": 0, "model": model}
    chunks = [
        {**base, "choices": [{"index": 0, "delta": {"role": "assistant", "content": "ok"},
                              "finish_reason": None}]},
        {**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
    ]
    if (body.get("stream_options") or {}).get("include_usage"):
        chunks.append({**base, "choices": [], "usage": USAGE})
    sse = "".join(f"data: {json.dumps(c)}\n\n" for c in chunks) + "data: [DONE]\n\n"
    return Response(sse, media_type="text/event-stream")


# Common mount points: /v1/..., /chat/completions, /openai/v1/...
for path in ("/v1/chat/completions", "/chat/completions", "/openai/v1/chat/completions",
             "/api/v1/chat/completions"):
    app.add_api_route(path, _complete, methods=["POST"])
