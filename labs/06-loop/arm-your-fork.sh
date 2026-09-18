#!/usr/bin/env bash
# Arm YOUR fork's CI workflows against YOUR sandbox subscription.
#
# Creates an OIDC app registration federated to your fork, grants it the roles the
# plan-only workflows need, and prints the five repository VARIABLES to add in your
# fork's UI: Settings -> Secrets and variables -> Actions -> Variables tab.
#
# Why variables and not secrets? With OIDC there is no credential to protect —
# client/tenant/subscription IDs are identifiers, and possessing them grants nothing
# without a matching federation subject. The security boundary is the federation:
# it binds both the names and immutable GitHub IDs of YOUR fork, so only workflows
# running in that exact repository can exchange tokens.
#
# Why never arm the upstream repo? On a public repo, the pull_request OIDC subject
# matches PRs from ANY fork, and pull_request runs the workflow file AS MODIFIED BY
# THE PR. Arming a public upstream hands every fork PR a path toward the subscription
# behind it. Your fork is low-traffic and yours; the course subscription is neither.
# (This reasoning is exam-relevant. You just read a trust-boundary analysis.)
set -euo pipefail

GH_USER="${1:?usage: ./arm-your-fork.sh <your-github-username-or-org>}"
REPO="${2:-cgeaz}"
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo ">> App registration: github-${REPO}-${GH_USER}"
APP_ID=$(az ad app create --display-name "github-${REPO}-${GH_USER}" --query appId -o tsv)
APP_OBJ=$(az ad app show --id "$APP_ID" --query id -o tsv)
az ad sp create --id "$APP_ID" --output none 2>/dev/null || true
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

GH_OWNER_ID=$(gh api "repos/${GH_USER}/${REPO}" --jq '.owner.id')
GH_REPO_ID=$(gh api "repos/${GH_USER}/${REPO}" --jq '.id')
OIDC_REPOSITORY="${GH_USER}@${GH_OWNER_ID}/${REPO}@${GH_REPO_ID}"

echo ">> Federated credentials for repo:${OIDC_REPOSITORY} (pull_request + main)"
for sub in "repo:${OIDC_REPOSITORY}:pull_request|pr" "repo:${OIDC_REPOSITORY}:ref:refs/heads/main|main"; do
  SUBJECT="${sub%|*}"; NAME="${sub#*|}"
  az ad app federated-credential create --id "$APP_OBJ" --parameters "{
    \"name\": \"${REPO}-${NAME}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${SUBJECT}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none 2>/dev/null || echo "   (${REPO}-${NAME} already exists)"
done

echo ">> Roles: read-only planning at mg-grc + resource-scoped sensitive refresh actions"
ROLE_NAME="CGE-AZ Terraform Plan Reader"
ROLE_ID=$(az role definition list --name "$ROLE_NAME" --query '[0].name' -o tsv)
if [ -z "$ROLE_ID" ]; then
  ROLE_FILE=$(mktemp)
  cat > "$ROLE_FILE" <<EOF
{
  "Name": "$ROLE_NAME",
  "Description": "Read governance resources for Terraform plans without write or secret-retrieval actions.",
  "Actions": [
    "*/read"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": ["/providers/Microsoft.Management/managementGroups/mg-grc"]
}
EOF
  ROLE_ID=$(az role definition create --role-definition "$ROLE_FILE" --query name -o tsv)
  rm -f "$ROLE_FILE"
fi
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "$ROLE_ID" --scope "/providers/Microsoft.Management/managementGroups/mg-grc" --output none 2>/dev/null || true

# The AzureRM provider must refresh the two Functions' runtime configuration. Those
# operations can disclose runtime storage keys/app settings, so never grant them at
# management-group or resource-group scope. Define them once, then assign only on the
# exact four plumbing resources that require them.
SENSITIVE_ROLE_NAME="CGE-AZ Terraform Sensitive Refresh Reader"
SENSITIVE_ROLE_ID=$(az role definition list --name "$SENSITIVE_ROLE_NAME" --query '[0].name' -o tsv)
if [ -z "$SENSITIVE_ROLE_ID" ]; then
  SENSITIVE_ROLE_FILE=$(mktemp)
  cat > "$SENSITIVE_ROLE_FILE" <<EOF
{
  "Name": "$SENSITIVE_ROLE_NAME",
  "Description": "Resource-scoped provider refresh actions for Function plumbing; never assign above an individual resource.",
  "Actions": [
    "Microsoft.Storage/storageAccounts/listKeys/action",
    "Microsoft.Web/sites/config/list/action"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": ["/providers/Microsoft.Management/managementGroups/mg-grc"]
}
EOF
  SENSITIVE_ROLE_ID=$(az role definition create --role-definition "$SENSITIVE_ROLE_FILE" --query name -o tsv)
  rm -f "$SENSITIVE_ROLE_FILE"
fi

mapfile -t SENSITIVE_RESOURCE_IDS < <(
  az storage account list --resource-group rg-grc-evidence-dev \
    --query "[?starts_with(name, 'stgrcfunc') || starts_with(name, 'stgrcrpt')].id" -o tsv
  az functionapp list --resource-group rg-grc-evidence-dev --query '[].id' -o tsv
)

if [ "${#SENSITIVE_RESOURCE_IDS[@]}" -ne 4 ]; then
  echo "Expected two runtime storage accounts and two Function Apps; refusing a broader fallback." >&2
  exit 1
fi

for RESOURCE_ID in "${SENSITIVE_RESOURCE_IDS[@]}"; do
  az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
    --role "$SENSITIVE_ROLE_ID" --scope "$RESOURCE_ID" --output none 2>/dev/null || true
done
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-grc-tfstate" --output none 2>/dev/null || true
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-grc-evidence-dev" --output none 2>/dev/null || true

STATE_SA=$(grep storage_account_name "$(dirname "$0")/../03-foundation/backend.hcl" 2>/dev/null | tr -d ' "' | cut -d= -f2 || echo "<from backend.hcl>")

cat <<EOF

Done. Add these five VARIABLES (not secrets — see header comment) in YOUR fork:
Settings -> Secrets and variables -> Actions -> Variables -> New repository variable

  AZURE_CLIENT_ID        $APP_ID
  AZURE_TENANT_ID        $TENANT_ID
  AZURE_SUBSCRIPTION_ID  $SUB_ID
  STATE_STORAGE_ACCOUNT  $STATE_SA
  OWNER_EMAIL            <your email>

Then enable the two workflows in your fork's Actions tab. Never add these to the
upstream GRCEngClub/cgeaz repo — its workflows are intentionally unarmed.
EOF
