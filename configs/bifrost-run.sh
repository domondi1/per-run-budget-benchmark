# Bifrost 1.6.3 (npm @maximhq/bifrost), Node v24.14.0. config.json from ./bifrost-config.json:
# OpenAI provider pointed at the fake upstream, retries off, four virtual keys, each with its own
# $0.0045 budget (reset 1d). Fresh keys per test: b (burst30 + wave2), s (seq15), sb (stream burst), ss (stream seq).
npm install --prefix . @maximhq/bifrost@1.6.3
mkdir -p data && cp bifrost-config.json data/config.json
OPENAI_API_KEY=bench VK_B=sk-bf-bench-b VK_S=sk-bf-bench-s VK_SB=sk-bf-bench-sb VK_SS=sk-bf-bench-ss \
  node_modules/.bin/bifrost -app-dir ./data -port 8090
# then, from the repo root (model ids are provider-prefixed in Bifrost):
#   python burst.py --url http://127.0.0.1:8090/v1/chat/completions --key sk-bf-bench-b --model openai/gpt-4o-mini --n 30 --nonce
#   python burst.py --url http://127.0.0.1:8090/v1/chat/completions --key sk-bf-bench-s --model openai/gpt-4o-mini --n 15 --sequential --nonce
