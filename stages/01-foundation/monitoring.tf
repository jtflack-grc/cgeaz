# Subscription Activity Log routing is governed as code. This replaces a portal or
# one-off CLI setting and ensures the tripwire has a durable evidence source.
resource "azurerm_monitor_diagnostic_setting" "subscription_activity" {
  name                       = "ds-activity-to-law"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.grc.id

  enabled_log {
    category = "Administrative"
  }

  enabled_log {
    category = "Security"
  }

  enabled_log {
    category = "Policy"
  }

  enabled_log {
    category = "Alert"
  }
}

# A real out-of-band change tripwire, not merely a saved query. Terraform and the
# remediation identity use workload identities; successful human writes by the
# accountable owner therefore represent portal/CLI activity requiring review.
resource "azurerm_monitor_action_group" "governance" {
  name                = "ag-cge-az-governance"
  resource_group_name = azurerm_resource_group.sandbox.name
  short_name          = "cgeazgov"

  email_receiver {
    name                    = "accountable-owner"
    email_address           = var.owner_email
    use_common_alert_schema = true
  }

  tags = {
    env     = var.environment
    purpose = "out-of-band-change-alerting"
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "human_change_tripwire" {
  name                = "alert-cge-az-human-change"
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = var.location

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.grc.id]
  severity             = 2
  enabled              = true
  description          = "Detect successful administrative writes performed directly by the accountable human owner."

  criteria {
    query = <<-KQL
      AzureActivity
      | where CategoryValue =~ "Administrative"
      | where ActivityStatusValue =~ "Success"
      | where Caller =~ "${var.owner_email}"
      | where OperationNameValue endswith "/write" or OperationNameValue endswith "/delete"
      | summarize ChangeCount=count()
    KQL

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.governance.id]
  }

  tags = {
    env     = var.environment
    purpose = "out-of-band-change-tripwire"
  }

  depends_on = [azurerm_monitor_diagnostic_setting.subscription_activity]
}
