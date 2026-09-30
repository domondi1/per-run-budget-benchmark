# otari 0.4.0 (mzdotai/otari:latest @ sha256:8ca32c6c...), in-container SQLite, port 8300
docker run -d --name bench-otari --network host -e OTARI_MASTER_KEY=sk-otari-bench -e OTARI_PORT=8300 -e OTARI_CONFIG_YAML='
default_pricing: true
port: 8300
providers:
  openai:
    api_key: bench
    api_base: "http://127.0.0.1:9400/v1"
' mzdotai/otari:latest otari serve
