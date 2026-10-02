# Admin AI operations — v5.0

The existing Admin section includes aggregate usage today/7 days, success/fallback/error counts, median latency, reported tokens, tool failures, feedback and monthly reservations. It requires `is_admin()` in the RPC; hiding the menu is not authorization. It contains no prompts, answers, applicant characteristics, notes or account list.

Provider: server-only `CME_AI_MODEL`; allowlisted models and OpenAI-only provider. Authentication uses Vercel OIDC by default. Keep any optional `AI_GATEWAY_API_KEY` in Vercel server environment only. Never copy credentials into frontend, logs, screenshots, documentation or GitHub. No provider credential is returned by a health endpoint.

For failures, inspect categorized aggregate errors, Vercel deployment/function health and AI Gateway usage. Do not enable request-content logging. `configuration` means missing/unsupported server configuration, `provider_limit` means credits/rate restriction, `provider_unavailable` or `timeout` is a transport/model problem, `grounding` means output/input evidence validation failed, `tool_failure` means an approved backend query failed. The UI labels fallback explicitly.

Quotas are fixed in migration 039: 3/min/user, 20/day/user, 100/month/project. Failed/blocked requests consume reservations and cannot be refunded through client RPCs. Metadata completion/feedback is owner-scoped and may be submitted by that owner; operational telemetry is best-effort and must not be treated as a financial billing ledger. Use provider billing for actual spend. No auto-reload or paid upgrade was authorized.

`cme-ai-metadata-retention-v50` removes metadata older than 40 days daily at 04:17 UTC. There is no persistent chat history to inspect or delete. Existing account deletion cascades on Auth user deletion. To disable inference safely, configure an unavailable model server-side; users retain core tools and clearly labeled fallback. Prefer a small reviewed code/configuration change over bypassing authentication or RLS.

Advisor review: private RLS with no policies is intentional deny-all; five public authenticated SECURITY DEFINER wrappers validate auth/ownership/admin and use empty search_path. Tests reject normal-user admin and cross-owner access. No new performance finding. Existing baseline warnings are documented in SECURITY.md.
