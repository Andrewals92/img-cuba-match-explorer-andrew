# Cuba Match Explorer v4.1

Interview season workspace, built on the deployed v4.0 static HTML/CSS/vanilla JavaScript architecture. Production acceptance status is recorded in VALIDATION-v4.1.md; authenticated browser/email acceptance must not be inferred from database or simulated DOM tests.

## Features

Interview Tracker supports invitation, scheduled, completed, cancelled and declined states, private notes/impressions, invitation date, fixed start/end instants, IANA timezone, virtual/in-person/hybrid format, private location/meeting URL, thank-you date and optional private ranked/position fields. Social, second-look and other events are separate records; imported historical reports are never converted to personal events.

Calendar includes upcoming, chronological agenda and month views. Mobile month view prioritizes an agenda. Events retain their saved timezone when the device timezone changes. Nonexistent DST wall times are rejected; repeated times require choosing their first or second occurrence. ICS uses UTC instants (interoperable with Apple/Outlook), stable UUID UIDs, CRLF escaping and UTF-8 line folding. An absent end defaults to one hour for calendar export and is labeled in the form. Google Calendar uses a standard event template URL, without OAuth. Notes, impressions and rank positions are never exported. Meeting URLs are excluded unless the user explicitly checks the calendar-export option; Google receives included fields when its link is opened.

My Programs is an account-wide private watchlist, unique by user/program UUID, with interest level and notes. Cycle application, signal and interview/ranked status derive from the user's reports and tracker events. Program Explorer, Profiles and Compare provide save/interview controls; profiles have a private My activity panel. Personal report rows offer an explicit Add to Interview Tracker action and reopen an already-linked interview. Custom program names are allowed and flagged as unmatched; a social uses a separate event rather than an extra interview field.

My Match adds next interview, upcoming events, tracker metrics, neutral scheduling/notes/ranked action items and saved-program summary. Declared invitation totals remain separate from detailed tracker events. The tracker shares the user's personal cycle choice, independently of community and comparable-cohort filters.

## Database

016_private_interview_workspace creates owner-only interview_events and user_program_watchlist, validation and duplicate constraints. Composite cycle/owner FK prevents linking another user's cycle. A narrow, non-callable private DEFINER trigger validates program metadata, IANA timezone and optional own-report linkage. No new public productivity RPC or admin exemption exists.

017_interview_cycle_fk_index covers the composite FK and removes a redundant single-column index identified by the advisor. 018_private_workspace_erasure extends the existing explicit delete-my-data operation to remove the user's new private records while preserving its prior behavior and narrowing search_path.

019_canonical_interview_timezones rejects ambiguous timezone abbreviations (UTC or a valid IANA region is required).

Historical migrations and import identities are unchanged. Service-worker cache and asset URLs use v4.1. Existing community features remain available; former interview community activity is retained in a collapsible section below the private tracker.

## Limits and future work

No email/SMS/background push infrastructure, objective program ratings or full rank-list workspace. Upcoming queries load only the selected cycle (maximum 1000 events) and account watchlist (maximum 500); large-account pagination is a future enhancement. In-app reminders are calculated when the app loads, without background alarms. Watchlist status does not invent an application when no report exists. Private JSON export of the original Mis datos records remains unchanged; calendar exports intentionally omit notes/rank information. Notifications in v4.2 can use event UUID, start_at, timezone, status and updated_at without changing calendar storage.

Created and owned by Andrew A Lopez Sanchez, MD, MBA.  
© 2026 Andrew A Lopez Sanchez, MD, MBA. All rights reserved.
