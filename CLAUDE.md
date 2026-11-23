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

Tests are pytest-based and drive real Docker containers.

> **DANGER — do not run the test suite against the developer's local Docker.** `test/conftest.py` (`remove_all_containers()`, called at the start of *every* test module via `DockerComposer.compose`) force-removes **every container on the Docker host**, with volumes, sparing only a container named `nginx-proxy-pytest`. This applies to `make test-*`, `test/pytest.sh`, and running any single test module. Without `--name nginx-proxy-pytest` the tester container deletes itself instead (exit 137) after possibly deleting others. Upstream designed this for disposable CI runners.

Run tests in GitHub Actions instead (disposable runners, both alpine and debian images):

```bash
gh workflow run test.yml -R yoldar/nginx-proxy --ref vouch-proxy   # push the branch first
gh run list -R yoldar/nginx-proxy -w Tests -L 3
gh run view <run-id> -R yoldar/nginx-proxy --log-failed
```

Only run locally if the user explicitly confirms after being told all their containers will be destroyed, or inside an isolated Docker daemon (e.g. a `docker:dind` container).

Log-format tests live in `test/test_logs/`; `test_log_json.py` asserts a prefix of the JSON line, so appending new keys at the end of the format is test-safe.

## Status & open items (as of 2026-11-24)

Done recently (see git log): `uid`/`imp` added to JSON log format; `http_referrer` removed from it (JWT leaked via `?token=` in Referer); **nginx bumped 1.27.2 → 1.31.9** to fix NGINX2Root (CVE-2026-123007 HTTP/2 RCE, CVE-2026-123633, CVE-2026-121810, CVE-2026-123634, CVE-2026-113425 — fixed in nginx 1.31.9+ / 1.30.7+ per nginx.org/en/security_advisories.html). HTTP/2 is on by default in this template, so the RCE applies; never go below 1.31.9 / 1.30.7.

Upstream nginx-proxy (`github.com/nginx-proxy/nginx-proxy`, not configured as a git remote) was still on nginx 1.31.6 (vulnerable) at that time — check its base image before syncing from it. This fork also lags upstream on docker-gen (0.14.2 vs 0.17.2) and forego.

Open items, discussed but deliberately not done yet:

- **Production image not rebuilt/pushed** since the log-format changes and the nginx 1.31.9 bump — run `./docker-build.sh` (default tag now `1.31.9-vouch-proxy`), update the image tag in the prod compose file, and **restart** (not reload) the proxy container. Verify with `docker exec <proxy> nginx -v`.
- `$http_referer` is still in the **non-JSON** default format (`nginx.tmpl` ~line 427). Left as-is because prod uses `LOG_JSON=true`; remove it too if consistency is wanted.
- The `request` JSON field logs the full URL including query string — a direct request to `/page?token=...` would still leak the token into logs. Mitigation would be logging a query-stripped variant via a `map` block (pattern: `nginx.tmpl` ~lines 352–420); not implemented, owner undecided.
- Root cause lives in the app, not the proxy: `app.rekassa.kz` puts a Firebase JWT in the `?token=` URL query param. Proper fix is app-side (stop passing tokens in URLs; consider a `Referrer-Policy` header).

## Conventions

- Commit messages: conventional-commit style (`feat:`, `fix:`, `refactor:`), imperative subject.
- After changing the JSON log format, update `docs/README.md` and verify end-to-end: run a container with `LOG_JSON=true`, curl with/without the relevant headers, check the emitted line is valid JSON.
