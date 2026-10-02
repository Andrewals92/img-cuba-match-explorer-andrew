# Privacy — v4.0

Existing applicant-cycle and program-report tables retain RLS. Imported applicants have no ordinary user owner and remain unreadable through raw-table queries to anonymous/normal accounts. Existing Applicant Explorer's threshold-protected anonymized cohort behavior remains; Program Profiles and Compare never return applicant rows.

The new public aggregate endpoint accepts 1–5 program UUIDs and an optional cycle. It requires consent, excludes rejected/inconsistent-cycle reports, deduplicates program reports per applicant cycle and counts distinct contributors for disclosure thresholds. Application counts and characteristic medians need at least 5 contributors; individual characteristic fields independently need 5 non-null contributors. Interview and completed-cycle Match counts and dated months need 3. Rates require valid application denominators and protect small outcome complements. Visa percentages require at least 5 people in each boolean category. Signal distributions are suppressed when a nonzero category has fewer than 3 contributors.

Suppressed and absent values are null, not zero. Imported invitation-only reports do not establish an application denominator. Monthly dates and latest visible activity are exposed only from eligible months, never from an individual's exact latest report timestamp. Public official-directory update dates are separate.

Personal totals and details remain on the authenticated own-data path. Only compare UUIDs and selected personal profile UUIDs are added to localStorage; v4 does not copy applicant data into a new browser store. Existing authentication storage remains unchanged. Compare URLs contain program IDs and cycle only.

The private identity registry stores reporting labels, specialty and state, with generated UUIDs. It stores no applicant IDs. Labels are not asserted to be official programs. New manual labels are registered only from consented profiles. Removing consent excludes their report data from aggregates; non-personal program metadata can remain in the directory.

Threshold suppression reduces disclosure risk; it is not differential privacy. Existing public analytics and anonymized comparable-cohort APIs remain under their prior policies. Do not interpret absence of activity as evidence about an individual.

## Private interview season workspace (v4.1)

Interview schedules, locations, meeting URLs, thank-you records, private notes, impressions, personal ranked/position information and watchlists are private to their owner. Administrators do not receive extra read access to these new tables. They are never part of community profile, comparison or cohort statistics. Saving an interview does not publish or overwrite a community report. Watchlist saves persist across cycles; activity is derived from your selected own cycle. Your explicit delete-my-data action includes these private records.

Calendar export shares event name, specialty, date/time, timezone and entered location. It omits notes, impressions and rank positions. Meeting URLs are included only when you explicitly select that export option. Opening Google Calendar sends the included event fields to Google; downloaded ICS files can be imported into Apple/Outlook or other calendar providers. Protect exported calendar files as personal information.

## v4.2 notifications and retention

The app stores your alert preferences, explicit specialty/state Radar filters, device push endpoint/encryption keys and private read state. Email/push are opt-in; in-app is enabled for relevant events. A saved program can be muted without removal. Quiet hours delay optional external channels without delaying in-app records. Email/push preferences are rechecked before dispatch; disabling a category cancels queued optional work.

Notifications contain concise public-program metadata or generic private reminder text. No private notes, rank positions, applicant rows or meeting URLs are sent to email/push. Lock-screen content stays generic. Community alerts reuse privacy-suppressed program statistics, never individual reports. Imports remain historical and do not generate personal reminders.

Notification records and their dependent queued jobs are retained 180 days. Attempt logs are pruned after 30 days. Push endpoint/key material remains until removed with account data, or a device is disabled after terminal failure; disabled records remain visible only to their owner/server. Use preferences to disable a device or all optional alerts. Existing Delete my data also erases new preferences, filters, subscriptions and notifications/outbox/delivery records. Keys/notes are not placed in localStorage; private screen state clears between sessions.


## v4.3

Only consented community contribution reports enter wave/signal analytics. Private tracker, watchlist notes and rank information do not. Weekly/monthly invitation buckets require 3 distinct people; signal cohorts require 5 plus zero-or-at-least-3 outcome complements. Canonical observations deduplicate person/program/cycle. Signals are never pooled across cycles. Personal fields from supplied external program lists are excluded by allowlist; source data and community samples stay separate.
