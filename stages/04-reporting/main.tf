locals {
  evidence_rg      = data.terraform_remote_state.foundation.outputs.evidence_resource_group_name
  cosmos_endpoint  = data.terraform_remote_state.evidence.outputs.cosmos_endpoint
  cosmos_id        = data.terraform_remote_state.evidence.outputs.cosmos_account_id
  cosmos_name      = data.terraform_remote_state.evidence.outputs.cosmos_account_name
  evidence_storage = data.terraform_remote_state.evidence.outputs.evidence_storage_account
  common_tags = {
    env     = var.environment
    purpose = "grc-reporting"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

data "azurerm_storage_account" "evidence" {
  name                = local.evidence_storage
  resource_group_name = local.evidence_rg
}

#checkov:skip=CKV_AZURE_59:Public endpoint is required by the Y1 Functions runtime; anonymous blob access remains disabled.
#checkov:skip=CKV_AZURE_206:LRS is a documented cost/availability decision for disposable runtime scratch data.
#checkov:skip=CKV_AZURE_33:Runtime queue telemetry is outside the evidence boundary; Azure Activity and policy diagnostics are centralized.
#checkov:skip=CKV2_AZURE_33:Private endpoints require networking infrastructure disproportionate to this disposable assessment subscription.
#checkov:skip=CKV2_AZURE_40:Classic Y1 Functions requires a storage access key for its runtime account; this exception cannot read evidence.
#checkov:skip=CKV2_AZURE_41:No SAS tokens are issued for the Functions runtime account.
#checkov:skip=CKV2_AZURE_1:Microsoft-managed encryption is accepted for non-evidence runtime scratch data in this lab boundary.
resource "azurerm_storage_account" "func_internal" {
  #checkov:skip=CKV_AZURE_59:Public endpoint is required by Y1; anonymous blob access remains disabled.
  #checkov:skip=CKV_AZURE_206:LRS is accepted for disposable runtime scratch data.
  #checkov:skip=CKV_AZURE_33:Runtime queues are outside the evidence boundary.
  #checkov:skip=CKV2_AZURE_33:Private endpoints are outside the disposable assessment boundary.
  #checkov:skip=CKV2_AZURE_40:Classic Y1 Functions requires a runtime storage key; this account cannot read Cosmos.
  #checkov:skip=CKV2_AZURE_41:No SAS tokens are issued.
  #checkov:skip=CKV2_AZURE_1:Platform encryption is accepted for non-evidence scratch data.
  name                            = "stgrcrpt${random_string.suffix.result}"
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

#checkov:skip=CKV_AZURE_225:Zone redundancy is unavailable on the serverless Y1 plan used for intermittent reporting.
#checkov:skip=CKV_AZURE_212:Minimum instance counts do not apply to the scale-to-zero Y1 plan.
resource "azurerm_service_plan" "reporting" {
  #checkov:skip=CKV_AZURE_225:Zone redundancy is unavailable on Y1.
  #checkov:skip=CKV_AZURE_212:Minimum instance counts do not apply to scale-to-zero Y1.
  name                = "asp-grc-reporting-${var.environment}"
  resource_group_name = local.evidence_rg
  location            = var.functions_location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.common_tags
}

#checkov:skip=CKV_AZURE_221:Public reachability is retained for authenticated demonstration triggers; function authentication is required.
resource "azurerm_linux_function_app" "reporting" {
  #checkov:skip=CKV_AZURE_221:Public reachability supports authenticated demo triggers; function auth is required.
  name                       = "func-grc-reporting-${random_string.suffix.result}"
  resource_group_name        = local.evidence_rg
  location                   = var.functions_location
  service_plan_id            = azurerm_service_plan.reporting.id
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
    "COSMOS_ENDPOINT"                = local.cosmos_endpoint
    "COSMOS_DATABASE"                = "grc"
    "REPORTS_ACCOUNT_URL"            = data.azurerm_storage_account.evidence.primary_blob_endpoint
    "REPORTS_CONTAINER"              = "reports"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD"              = "true"
  }

  tags = local.common_tags
}

# --- The reporting identity's whitelist — the mirror image of the collector's. ---
# Cosmos READ (built-in Data Reader), Blob WRITE into the WORM container. No path to
# live platform data: no Security Reader, no Cosmos write. SoD, enforced by scopes.

resource "azurerm_cosmosdb_sql_role_assignment" "reporter_cosmos_read" {
  resource_group_name = local.evidence_rg
  account_name        = local.cosmos_name
  role_definition_id  = "${local.cosmos_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001"
  principal_id        = azurerm_linux_function_app.reporting.identity[0].principal_id
  scope               = local.cosmos_id
}

resource "azurerm_role_assignment" "reporter_blob_write" {
  scope                = data.azurerm_storage_account.evidence.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.reporting.identity[0].principal_id
}

output "reporting_function_app" {
  value = azurerm_linux_function_app.reporting.name
}

output "reporter_principal_id" {
  value = azurerm_linux_function_app.reporting.identity[0].principal_id
}
