# Capstone Evidence Register

This register distinguishes implementation evidence from operating-effectiveness
evidence. Every verified item below is backed by a repository artifact, an Azure
runtime result, or an immutable GitHub workflow record.

| ID | Rubric area | Proof required | Status | Artifact or link |
|---|---|---|---|---|
| EV-01 | IaC quality | Clean fmt, validate, TFLint, Checkov, secret scan, and policy tests | Verified | [Compliance gate](../evidence/validation/compliance-gate.json), [PR #1](https://github.com/jtflack-grc/cgeaz/pull/1) |
| EV-02 | Controls | Public storage request denied by Azure Policy | Verified | [Azure Policy denial](../evidence/validation/azure-policy-deny.txt) |
| EV-03 | Controls | Candidate owner control moves from noncompliant to compliant | Verified | [Before](../evidence/validation/owner-control-before.json), [after](../evidence/validation/owner-control-after.json) |
| EV-04 | Identity | Collector, reporter, remediation, and OIDC effective roles | Verified | [Effective role assignments](../evidence/validation/effective-role-assignments.json) |
| EV-05 | Integrity | Two distinct scheduled executions preserve historical run records | Verified with disclosed source limitation | [Scheduled run history](../evidence/validation/scheduled-run-history.json) |
| EV-06 | Integrity | Reports trace to a scheduled source run and cryptographic hashes | Verified | [Report ledger](../evidence/validation/report-ledger.json), [POA&M generation](../evidence/validation/poam-generation.json), [SAR generation](../evidence/validation/sar-generation.json) |
| EV-07 | Integrity | Existing retained report cannot be overwritten | Verified | [Blocked overwrite](../evidence/validation/worm-overwrite-blocked.txt), [blocked deletion](../evidence/validation/worm-delete-blocked.txt) |
| EV-08 | Operations | Insecure pull request is blocked while unrelated stages pass | Verified | [Blocked PR evidence](../evidence/validation/blocked-pr.json), [PR #2](https://github.com/jtflack-grc/cgeaz/pull/2) |
| EV-09 | Operations | Clean pull request passes every configured stage | Verified | [Compliance gate](../evidence/validation/compliance-gate.json), [PR #1](https://github.com/jtflack-grc/cgeaz/pull/1) |
| EV-10 | Operations | Deliberate drift opens a redacted issue and convergence creates none | Verified | [Drift issue](../evidence/validation/drift-issue.json), [detection run](../evidence/validation/drift-workflow-run.json), [clean run](../evidence/validation/drift-clean-run.json), [issue #5](https://github.com/jtflack-grc/cgeaz/issues/5) |
| EV-11 | Operations | Direct human changes reach Log Analytics and fire Azure Monitor | Verified | [Ingested events](../evidence/validation/human-change-log.json), [fired alert](../evidence/validation/human-change-alert-fired.json), [alert configuration](../evidence/validation/human-change-alert-config.json) |
| EV-12 | Closed loop | Human-authorized remediation succeeds as the named identity | Verified | [Task](../evidence/validation/remediation-task.json), [identity-matched activity](../evidence/validation/remediation-activity-log.json), [before](../evidence/validation/remediation-before.json), [after](../evidence/validation/remediation-after.json) |
| EV-13 | Closed loop | Re-evaluation records the corrected compliance state | Verified | [Noncompliant state](../evidence/validation/remediation-policy-state-before.json), [compliant state](../evidence/validation/remediation-policy-state-after.json) |
| EV-14 | Documentation | Architecture, control mappings, limitations, and teardown are documented | Verified | [Architecture](ARCHITECTURE.md), [controls](CONTROLS.md), [repository guide](../README.md), [loop guide](../labs/06-loop/README.md) |

## Evidence-handling rules

Subscription IDs, tenant IDs, object IDs, function keys, access tokens, and personal
billing information are excluded or redacted. Runtime keys used to invoke authenticated
Functions remained shell-only and were unset after use.

No synthetic or backdated findings were inserted. Defender for Cloud returned zero
assessment records during the observation window. EV-05 therefore proves two genuine
timer executions, separate historical run-ledger records, and explicit zero-source
counts; it does not claim that a finding existed when Azure returned none. The POA&M
and SAR correctly report zero findings and retain their source run ID.

The controlled remediation resource was deleted after Azure Policy recorded its
transition from noncompliant to compliant. Drift issues were closed only after a
subsequent five-stage workflow produced no new findings.
