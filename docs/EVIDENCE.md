# Capstone Evidence Register

This register is updated only after runtime proof exists. Repository configuration is
implementation evidence; screenshots, command output, workflow runs, and stored
artifacts are operating-effectiveness evidence.

| ID | Rubric area | Proof required | Status | Artifact or link |
|---|---|---|---|---|
| EV-01 | IaC quality | Clean fmt/validate/tflint/checkov across every stage | Pending | CI run |
| EV-02 | Controls | Public storage request denied by Azure Policy | Pending | Redacted command output |
| EV-03 | Controls | Candidate owner control reports compliance state | Pending | Policy state export |
| EV-04 | Identity | Collector, reporter, remediation, and OIDC effective roles | Pending | Role export |
| EV-05 | Integrity | Two scheduled runs retain the same assessment historically | Pending | Redacted Cosmos query |
| EV-06 | Integrity | Report ledger traces to source run and hash | Pending | POA&M JSON + source query |
| EV-07 | Integrity | Existing report cannot be overwritten during retention | Pending | Failed overwrite output |
| EV-08 | Operations | Bad pull request blocked by OPA | Pending | GitHub Actions link |
| EV-09 | Operations | Clean pull request passes all stages, including Stage 02 | Pending | GitHub Actions link |
| EV-10 | Operations | Deliberate drift opens an issue | Pending | GitHub issue + workflow link |
| EV-11 | Operations | Direct human change raises Azure Monitor alert | Pending | Alert export/email |
| EV-12 | Closed loop | Remediation succeeds as named identity | Pending | Task + Activity Log caller |
| EV-13 | Closed loop | Recollection/report reflects corrected state | Pending | Before/after run IDs |
| EV-14 | Documentation | Architecture, mappings, limitations, and teardown complete | Implemented | Repository documents |

Evidence must be redacted before publication. Subscription IDs, tenant IDs, object
IDs, function keys, access tokens, and personal billing information do not belong in
this repository.

Synthetic records may be used for immediate report-format testing only and must be
marked as synthetic. EV-05 is satisfied only by distinct runs emitted by the deployed
timer; manual or seeded records do not count as operating-effectiveness evidence.
