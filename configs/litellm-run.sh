# LiteLLM 1.103.0 (ghcr.io/berriai/litellm-database:main-stable @ sha256:f4f114b1...) + Postgres 16
docker run -d --name bench-pg -p 5432:5432 -e POSTGRES_PASSWORD=pw -e POSTGRES_DB=litellm postgres:16-alpine
docker run -d --name bench-litellm --network host -v $PWD/litellm-config.yaml:/app/config.yaml \
  ghcr.io/berriai/litellm-database:main-stable --config /app/config.yaml --port 4000
# default end-user budget variant: create budget first, then restart with litellm-config-default-enduser.yaml
curl -X POST localhost:4000/budget/new -H "Authorization: Bearer sk-bench-master" -H "Content-Type: application/json" \
  -d '{"budget_id":"bench-run-default","max_budget":0.0045}'
