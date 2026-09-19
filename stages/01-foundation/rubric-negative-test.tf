resource "azurerm_storage_account" "rubric_negative_test" {
  name                            = "stcgeazrubricbad01"
  resource_group_name             = azurerm_resource_group.sandbox.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = true
  shared_access_key_enabled       = true
}
