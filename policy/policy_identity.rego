# Gate rule: a policy assignment carrying remediation effects without an identity
# applies cleanly and then silently never remediates. Make that mistake unmergeable.
package main

import rego.v1

assignment_types := {
	"azurerm_management_group_policy_assignment",
	"azurerm_subscription_policy_assignment",
	"azurerm_resource_group_policy_assignment",
}

# Regulatory/audit-only assignments do not execute remediation and therefore do
# not need an identity. This explicit allowlist keeps the exception narrow and
# reviewable instead of weakening the rule for every subscription assignment.
audit_only_assignments := {"nist-csf-20"}

deny contains msg if {
	some rc in input.resource_changes
	rc.type in assignment_types
	rc.change.actions[_] != "delete"
	not rc.change.after.name in audit_only_assignments
	not rc.change.after.identity
	msg := sprintf("%s: policy assignments must carry an identity block (remediation effects silently no-op without one)", [rc.address])
}
