# Architecture and Trust Boundaries

## Design claim

The system separates observation, evidence custody, reporting, authorization, and
remediation. No single workload identity can both alter Azure posture and rewrite the
resulting narrative.

## Identity matrix

| Principal | Scope | Permitted | Explicitly absent |
|---|---|---|---|
| Collector managed identity | Subscription + Cosmos account | Read Defender assessments; append evidence | Policy writes, resource writes, report publication |
| Reporter managed identity | Cosmos account + evidence storage | Read stored evidence; write immutable reports | Live Azure posture reads, Cosmos writes, remediation |
| Remediation user-assigned identity | Sandbox management group | Monitoring configuration and approved storage-property correction | Data reads, general Contributor, Owner |
| GitHub OIDC service principal | Sandbox management group + state/evidence data scopes + five exact provider-refresh resources | Terraform refresh/plan, state access, evidence-container reads; key/config refresh only on the two runtime accounts, two Function Apps, and one Cosmos account | Apply, RBAC writes, broad secret reads, interactive login |
| Human owner | Subscription | Authorize changes and respond to exceptions | Exemption from logging or drift detection |

## Evidence lifecycle

1. Defender and Azure Policy evaluate live resources. During the bounded assessment
   window, the collector runs every fifteen minutes so operating history is produced
   by the deployed timer rather than by a burst of manual demonstrations.
2. The collector obtains a short-lived token through managed identity.
3. A sweep receives a UUID `runId` and UTC `collectedAt` timestamp. A completed-run
   ledger records whether the trigger was scheduled or manual and the exact number
   of assessments returned, including an honest zero from a not-yet-populated API.
4. Each assessment document ID hashes the run, assessment, and resource. Repeated assessments
   therefore create historical snapshots rather than overwriting prior posture.
5. Reports select the latest complete run, never live platform data.
6. The POA&M JSON records its source run, timestamp, query, finding count, and a
   SHA-256 digest of the emitted items.
7. Reports are written to a versioned container with time-based immutability.

## Change-control loop

| State | Policy effect | Human meaning |
|---|---|---|
| Audit | Observe only | Establish scope and false-positive rate |
| Dry-run | Modify definition with `DoNotEnforce` | Human creates the remediation task |
| Enforce | Modify with enforcement | Approved control operates automatically |

GitHub pull requests plan every Terraform stage and send the JSON plans through OPA.
Nightly plans compare code with reality. Independently, Azure Activity Log is routed
to Log Analytics, where a scheduled query alerts on successful writes made directly
by the accountable human identity. The two detectors answer different questions:
Terraform asks *what differs?*; the Activity Log asks *who changed it?*

## Deliberate lab boundary

The WORM policy is unlocked so a disposable subscription can be destroyed. The
GitHub planning identity has limited list operations because the AzureRM provider must
refresh some managed-service configuration. These are recorded assessment-boundary
decisions, not claims that the same choices are appropriate for production.
