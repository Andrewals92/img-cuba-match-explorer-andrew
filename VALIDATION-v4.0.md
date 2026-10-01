# v4.0 validation — in progress

- Baseline source verified against GitHub main a71efdc39e618558e585ebd23a44bf8cc6d36f20.
- Migrations 013 and 014 applied successfully.
- Baseline remains 36 imported profiles / 338 invitations / 14 matches, zero duplicate imported report tuples.
- Transactional SQL tests passed: n=2 suppression; n=6 counts/medians/rates; consent exclusion; incomplete cycles; own-data read/update; RLS isolation; self-promotion denied; admin RPC denied to normal users; public aggregates available. Synthetic rows rolled back.
- Personal-summary tests passed: declared totals including zero, detail deduplication, selected-cycle isolation and invalid-rate handling.
- Five-program aggregate EXPLAIN ANALYZE: approximately 41 ms before the join indexes, no disk spill.
- Production/browser/auth verification is pending. This document must be finalized after deployment smoke tests.
