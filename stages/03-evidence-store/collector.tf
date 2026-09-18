# --- The collector Function App: timer-triggered Python, managed identity, zero keys. ---
# One app for collectors, a separate app (stage 04) for reporting: the Function App is
# the identity boundary, and no identity both writes evidence and generates reports.

# Internal plumbing storage for the Functions runtime (NOT the evidence store —
# that account has shared keys disabled; this one is the app's own scratch space).
#checkov:skip=CKV_AZURE_59:Public endpoint is required by the Y1 Functions runtime; anonymous blob access remains disabled.
#checkov:skip=CKV_AZURE_206:LRS is a documented cost/availability decision for disposable runtime scratch data.
#checkov:skip=CKV_AZURE_33:Runtime queue telemetry is outside the evidence boundary; Azure Activity and policy diagnostics are centralized.
#checkov:skip=CKV2_AZURE_33:Private endpoints require networking infrastructure disproportionate to this disposable assessment subscription.
#checkov:skip=CKV2_AZURE_40:Classic Y1 Functions requires a storage access key for its runtime account; this exception cannot reach evidence storage.
#checkov:skip=CKV2_AZURE_41:No SAS tokens are issued for the Functions runtime account.
#checkov:skip=CKV2_AZURE_1:Microsoft-managed encryption is accepted for non-evidence runtime scratch data in this lab boundary.
resource "azurerm_storage_account" "func_internal" {
  #checkov:skip=CKV_AZURE_59:Public endpoint is required by Y1; anonymous blob access remains disabled.
  #checkov:skip=CKV_AZURE_206:LRS is accepted for disposable runtime scratch data.
  #checkov:skip=CKV_AZURE_33:Runtime queues are outside the evidence boundary.
  #checkov:skip=CKV2_AZURE_33:Private endpoints are outside the disposable assessment boundary.
  #checkov:skip=CKV2_AZURE_40:Classic Y1 Functions requires a runtime storage key; this account cannot read evidence.
  #checkov:skip=CKV2_AZURE_41:No SAS tokens are issued.
  #checkov:skip=CKV2_AZURE_1:Platform encryption is accepted for non-evidence scratch data.
  name                            = "stgrcfunc${random_string.suffix.result}"
  resource_group_name             = local.evidence_rg
  location                        = var.functions_location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  tags = local.common_tags
}

#checkov:skip=CKV_AZURE_225:Zone redundancy is unavailable on the serverless Y1 plan used for intermittent evidence collection.
#checkov:skip=CKV_AZURE_212:Minimum instance counts do not apply to the scale-to-zero Y1 plan.
resource "azurerm_service_plan" "collectors" {
  #checkov:skip=CKV_AZURE_225:Zone redundancy is unavailable on Y1.
  #checkov:skip=CKV_AZURE_212:Minimum instance counts do not apply to scale-to-zero Y1.
  name                = "asp-grc-collectors-${var.environment}"
  resource_group_name = local.evidence_rg
  location            = var.functions_location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption: pay per execution. Pennies.
  tags                = local.common_tags
}

#checkov:skip=CKV_AZURE_221:Public reachability is retained for authenticated demonstration triggers; function authentication is required.
resource "azurerm_linux_function_app" "collectors" {
  #checkov:skip=CKV_AZURE_221:Public reachability supports authenticated demo triggers; function auth is required.
  name                       = "func-grc-collectors-${random_string.suffix.result}"
  resource_group_name        = local.evidence_rg
  location                   = var.functions_location
  service_plan_id            = azurerm_service_plan.collectors.id
  storage_account_name       = azurerm_storage_account.func_internal.name
  storage_account_access_key = azurerm_storage_account.func_internal.primary_access_key
  https_only                 = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "COSMOS_ENDPOINT"                = azurerm_cosmosdb_account.evidence.endpoint
    "COSMOS_DATABASE"                = azurerm_cosmosdb_sql_database.grc.name
    "SUBSCRIPTION_ID"                = local.subscription
    "OWNER_EMAIL"                    = var.owner_email
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD"              = "true"
  }

  tags = local.common_tags
}

# --- The collector identity's whitelist: read posture, write evidence. Nothing else. ---

# Security Reader at the subscription: read Defender assessments, change nothing.
resource "azurerm_role_assignment" "collector_security_reader" {
  scope                = "/subscriptions/${local.subscription}"
  role_definition_name = "Security Reader"
  principal_id         = azurerm_linux_function_app.collectors.identity[0].principal_id
}

# Cosmos data-plane write. "Cosmos DB Built-in Data Contributor" (00000000-0000-0000-0000-000000000002)
# is a Cosmos-native data-plane role, not an ARM role — control plane vs data plane, again.
resource "azurerm_cosmosdb_sql_role_assignment" "collector_cosmos_write" {
  resource_group_name = local.evidence_rg
  account_name        = azurerm_cosmosdb_account.evidence.name
  role_definition_id  = "${azurerm_cosmosdb_account.evidence.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_linux_function_app.collectors.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.evidence.id
}
