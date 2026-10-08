# New Program Radar / ERAS Program Watch

The monitor reads the official ACGME ADS public program search and the AAMC ERAS participating-program catalogue independently. It discovers specialties and the current ERAS season from their source pages. Programme IDs join the catalogues; names alone never establish identity or participation.

- ACGME: all specialty and subspecialty selector options; directory status distinguishes accredited, future accredited, pre-accreditation, unaccredited combined, and withdrawn.
- AAMC: every specialty linked by the catalogue, including fellowship and combined specialties; explicit participation states, current season, and the official New Program label. Multiple tracks sharing one ID retain separate participation states.
- The first successful snapshot establishes a baseline. Later additions, status changes and missing listings are recorded idempotently. Missing listings are not reclassified as withdrawn or not participating.
- Incomplete responses, season mismatches, unknown participation states, duplicate malformed identities and a greater-than-30% drop preserve the prior snapshot and report an error. Explicit empty source pages are supported.
- Source and specialty attempt/success times are separate. Failures never update successful verification timestamps. The interface shows coverage, failures and stale data; an empty radar is not proof of no new programmes.
- The existing `cuba-match-acgme-monitor` Supabase cron job runs every ten minutes, processing four specialties per source. Internal Medicine gets hourly priority, and oldest attempts rotate so failures cannot starve other specialties. This is periodic public-catalogue synchronization, not a real-time official API or private MyERAS connection.

The scheduler uses a server-only dispatch token and a four-minute lease. Raw snapshot tables and write RPCs are restricted to service credentials. Browser reads go through the existing protected Vercel gateway. No secret is shipped to the client.

## Verification

`node --test tests/catalog-parser.test.mjs`

`node tests/catalog-radar-dom.test.cjs` and `node tests/notifications-dom.test.cjs` (jsdom required in the verification environment).

`tests/catalog-sync.sql` runs transactionally and rolls back: baseline suppression, partial snapshot preservation, event idempotence, absent-record semantics and access restrictions.

## Operations

Inspect `program_catalog_health()` and `acgme_sync_runs` (`details.mode = dual_catalog`). `completed` means that batch succeeded; total coverage is reported separately. A `partial` batch does not imply either source has complete coverage.

A trusted database operator can request a bounded catch-up batch with `select cme_private.catalog_tick(null,12);`. The lease prevents overlap with scheduled work. Resolve source-format failures in the parser; do not mark a failed specialty as verified. Reapply a full validated snapshot through the worker after correction.
