# @relayplane/proxy 1.9.69 on node v24.14.0; config.json from ./relayplane-config.json (rate limit raised to 10000 rpm)
npm install --prefix . @relayplane/proxy
mkdir -p home/.relayplane && cp relayplane-config.json home/.relayplane/config.json
HOME=$PWD/home RELAYPLANE_OPENAI_BASE_URL=http://127.0.0.1:9400/v1 OPENAI_API_KEY=bench node_modules/.bin/relayplane start
