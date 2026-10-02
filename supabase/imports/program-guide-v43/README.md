# Program guide enrichment

The original 33 program-source batches are unchanged baseline artifacts. Migration 034 applies the 19 identity corrections by source key/ACGME, the 702 institutional URLs and the program-only application-trend/video fields. Migration 035 repairs redirected links. The running catalog combines those changes; do not replay baseline files over an enriched deployment.

`identity-resolutions.json` preserves evidence for 19 aliases. `institutional-websites.json` is the final audited link map (program versus institution scope). `program-complements.json` contains only additive program metadata and no contact records or applicant information. The extraction helper applies the same allowlist and identity corrections when producing a fresh source set. Original provenance remains internal; the public RPCs and UI use neutral metadata kinds.
