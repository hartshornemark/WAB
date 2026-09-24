# B3 table verification — 17 September 2026

Applied migration passenger_weights_byclass_and_protections to ffmadtrcirrzywdqahbu.

Live rollback checks passed for default/named rows, duplicate prevention including NULL defaults, valid class membership, referenced class/variation removal and rename rejection, priority-only class changes, label edits, required/positive/nonnegative weights, baggage inclusion and retained inactive values, remarks limit, Solution Administrator and Carrier Administrator writes, Configuration Editor read-only access, cross-carrier insert/ownership denial, unassigned and anonymous reads.

Verified RLS enabled, four table policies, no saved weight rows and no temporary TST variation remaining. Existing passenger-weight values were not modified. Test role fixtures rolled back.

Security advisor reports the pre-existing 11 informational default-deny table notices and leaked-password-protection warning; no new findings.

Class membership writes touch the carrier class row to serialize concurrent class edits and cause serialization failure for stale repeatable-read snapshots. Concurrent multi-session stress testing was not run. Touches preserve all class values but advance their revision, so an open class editor may need a refresh after a passenger-weight save.

No application code changed. B3 UI, invoker read/save APIs, stale-edit handling and full browser verification remain to be implemented.
