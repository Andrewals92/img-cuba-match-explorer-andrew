# AI data and grounding — v5.0

## Trust boundaries

Browser -> same-origin Vercel function -> Supabase Auth `get user` -> approved RPC/owner-scoped REST reads -> Vercel AI Gateway with OpenAI-only provider routing. No service-role key is needed. Models cannot supply table names, SQL, URLs, user IDs or mutations. Context program IDs must be bounded UUIDs; owned profiles are checked by the database. Calls never fetch arbitrary websites.

Free questions use one strict routing tool. Context buttons use fixed routes. The optional second call selects allowed fact IDs and caution IDs under JSON Schema. All displayed statements are assembled server-side from returned evidence; model prose, unknown IDs and invented claims are discarded. Official sources and retrieved text are data, never instructions. This is extractive assisted synthesis, not an unrestricted chatbot.

## Sources and limitations

- Own data: selected applicant cycle, declared totals, deduplicated report counts, saved program IDs and (when asked) upcoming program/time/timezone. Access is scoped to the authenticated UID even for admins.
- Community: server-suppressed aggregate cohorts, program statistics, waves and signals. No raw imported or current applicant rows. Five distinct people for detailed cohorts; three for protected program outcomes/waves plus complementary suppression. The owner is excluded from their own cohort.
- Catalog: stable UUID/ACGME identity, location, specialty, accreditation and source freshness when available. A community label is never asserted to be an official identity.
- Program guide: dated historical program-level signal rates and recorded requirements. Missing denominators remain explicit. Requirements must be reconfirmed on the institutional site. The guide's cycle is distinct from the community selector.
- Official links: institutional, ACGME, FREIDA and Residency Explorer links; no protected-page scraping. A link-verification date is not a page retrieval date. No live institutional website content is retrieved by v5.0.

The cohort RPC exposes `queried_at` and a null `updated_at` when aggregate source freshness is unavailable. Query time must never be presented as evidence freshness. In-progress cycles are separate; absence of a Match report is not a confirmed No Match outcome. Program discovery ordering describes observed interview frequency, never quality or personal likelihood.

## Privacy and retention

Each send requires visible consent. Questions and the minimum necessary evidence are processed by Vercel AI Gateway/OpenAI. The application does not persist prompts or answers, and makes no promise about provider retention beyond the provider's applicable terms. Six answers maximum remain only in page memory; logout/account change/reload/clear removes them. Each question is independent; chat history is not re-sent.

Private notes, meeting URLs, rank-list positions, verification documents, emails and profile identities are omitted from model context. Prompt limits cannot prevent a user typing private content manually; the consent text asks them not to do so. Authentication tokens are used only for authentication/backend access, never inserted into prompts.

Operational metadata stores account ownership, answer ID, mode, status, categorized error, latency, token counts, source categories, up to five program IDs and optional feedback. No free-text feedback or chat history. Retention is 40 days; admin sees aggregates only. Personalized responses have `private, no-store`; the service worker bypasses `/api/` and private/no-store responses. No shared answer cache.

## Financial bounds

Atomic limits: 3 requests/minute and 20/day per user; 100/month for the whole project. Failed requests retain their reservation. Maximum two model calls, 700 + 1,100 output tokens, bounded inputs (22 KB each), 1,200-character question and at most five selected programs. Each provider call times out at 14 seconds; function maximum is 60 seconds. Metadata has indexed owner/time and time access paths. These are consumption bounds, not a guaranteed dollar price; rates and included credits depend on the configured provider. No automatic credit reload.
