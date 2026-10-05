# v5.2 — browser and data access protection

Published 2026-10-05. Preserves v5.1 public pseudonymous cohorts, small samples, program/signal details, founder page and supplied brand assets.

## Delivered

- BotID Basic checks on the server gateway and built-in assistant; no paid Deep Analysis mode.
- Same-origin, allowlisted gateway, unchanged user JWTs and RLS, request quotas per hashed IP and user, no-store API responses.
- Migrations 042 and 043 install and activate the PostgREST pre-request guard. An ordinary account token alone cannot access data outside the trusted server gateway. Maintenance service-role access remains functional.
- Known AI and headless user-agent deny rule; robots/no-index/no-snippet directives; CSP, frame restrictions and HSTS.
- Static build allowlist excludes database imports, SQL, server source and tests from website downloads.
- Copy/print/context-menu deterrents, per-tab watermarks, content hiding in background tabs and session-only browser token storage. Editable fields and intentional own-data exports remain usable.

## Verification

- Production deployment 6f36ace324041ec96384aae41c3ba1f5f1f497a5 reached READY before database enforcement was activated.
- Browser cohort search succeeded before and after activation: 13 comparable profiles, 796 available declared applications, 168 available declared interviews, 8 documented matches and 5 unknown outcomes with the existing filters.
- A request identified as GPTBot returned HTTP 403. An unsigned gateway request returned HTTP 403 `browser_verification_required`.
- A direct anonymous Supabase data request returned HTTP 401 / SQLSTATE 42501 with the direct-access-denied message after activation.
- The excluded import URL returned HTTP 404. Production security headers were present.
- Transactional SQL assertions passed for anonymous/authenticated direct-access denial, forged proof rejection, trusted proof acceptance, service maintenance, quota enforcement and private configuration ACLs; the test rolled back.
- Seven gateway unit checks, 17 assistant checks, public-cohort DOM regression checks, JavaScript syntax and static build passed.
- Supabase advisors: expected private tables with RLS and no client policies; existing intentionally callable security-definer APIs; existing leaked-password protection warning remains. No claim of a full penetration test or verified authenticated account lifecycle is made.

## Explicit limitations

The verification browser controlled by this assistant was accepted by BotID and could read the public profiles. This is direct evidence that the controls do not block every AI-operated browser. User-agent rules are spoofable and robots directives are advisory.

Websites cannot prevent operating-system screenshots, foreground screen recording, external cameras, browser extensions or a permitted viewer copying rendered content. Copy restrictions and watermarks are deterrents, not DRM. `display-capture=()` prevents this page initiating screen capture, not another application recording it.

GitHub repository visibility is still public. The connector has no visibility-update action and the browser requires GitHub sign-in before it can be made private. Existing forks and downloaded copies cannot be recalled.

The managed Vercel AI Bots/Bot Protection configuration could not be enabled through the connector: active-config GET and config PUT returned 404. The code-based edge deny rule is active; the managed rules are not claimed as active. Browser fallback to the Vercel administration panel requires user approval because the available connector failed.

Operational details and rollback order are in SECURITY.md. No user data was deleted or rewritten.
