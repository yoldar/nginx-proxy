# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

Fork of [nginx-proxy/nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) — automated nginx reverse proxy for Docker containers. Working branch is `vouch-proxy`; the fork's deltas vs upstream:

- **Vouch Proxy SSO support**: per-container `VOUCH_PRIVATE_URL` / `VOUCH_PUBLIC_URL` env vars enable `auth_request /vouchValidate` protection for a vhost (see `nginx.tmpl` ~lines 640–920, `docker-compose-example.yml`).
- **Customized log formats**: the default (non-JSON) format and the `LOG_JSON=true` JSON format are modified. JSON format includes `uid` (`$http_x_user_uid`) and `imp` (`$http_x_impersonate_slack_id`) request headers; `http_referrer` was deliberately removed from the JSON format because Referer can leak secrets in query params (e.g. `?token=<JWT>`). Do not re-add it.
- `server_tokens off` enabled globally.

## Architecture

- **`nginx.tmpl` is the single source of truth.** The entire nginx config is generated from this Go template by docker-gen (`app/Procfile`: `docker-gen -watch -notify "nginx -s reload" /app/nginx.tmpl /etc/nginx/conf.d/default.conf`). There are no other conf files to edit.
- Proxy-container env vars reach the template as `$globals.Env.*`; per-backend-container env vars via `groupByKeys` (see the `VOUCH_*` handling for the pattern).
- Log formats are assembled at `nginx.tmpl` ~lines 422–440 (`log_format vhost ...`, controlled by `LOG_FORMAT`, `LOG_FORMAT_ESCAPE`, `LOG_JSON`). nginx `escape=json` logs a missing header as `""` — keys cannot be conditionally omitted.
- User-facing docs for log options: `docs/README.md` ("JSON log format" section) — keep the JSON example in sync with `nginx.tmpl`.

## Build & deploy

- `./docker-build.sh` — buildx for linux/amd64 from `Dockerfile.alpine`, tags and pushes `yoldarz/nginx-proxy:<nginx-version>-vouch-proxy`. Bump the tag in the script when upgrading nginx.
- Deployed via docker compose; `docker-compose-example.yml` shows the intended stack (proxy + vouch-proxy + acme-companion).

## Testing

Tests are pytest-based and drive real Docker containers (need Docker running).

```bash
make test-alpine        # full suite: builds web test image + proxy test image, runs everything (slow)
```

Run a subset non-interactively (the stock `test/pytest.sh` uses `-it` and must be run from the repo root; the direct equivalent):

```bash
docker build --build-arg NGINX_PROXY_VERSION="test" -f Dockerfile.alpine -t nginxproxy/nginx-proxy:test .
docker build --pull -t nginx-proxy-tester -f test/requirements/Dockerfile-nginx-proxy-tester test/requirements
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD/test" nginx-proxy-tester test_logs/
```

Log-format tests live in `test/test_logs/`; `test_log_json.py` asserts a prefix of the JSON line, so appending new keys at the end of the format is test-safe.

## Conventions

- Commit messages: conventional-commit style (`feat:`, `fix:`, `refactor:`), imperative subject.
- After changing the JSON log format, update `docs/README.md` and verify end-to-end: run a container with `LOG_JSON=true`, curl with/without the relevant headers, check the emitted line is valid JSON.
