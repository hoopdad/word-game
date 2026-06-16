data "azurerm_client_config" "current" {}

locals {
  # Derived, human-readable names for the spoke workload resources.
  normalized_alnum = join("", regexall("[a-z0-9]", lower(local.spoke_prefix)))
  normalized_dns   = join("", regexall("[a-z0-9-]", lower(local.spoke_prefix)))

  acr_name        = substr("acr${local.normalized_alnum}", 0, 50)
  key_vault_name  = substr("kv${local.normalized_alnum}", 0, 24)
  cosmos_account  = substr("${local.normalized_alnum}cosmos", 0, 44)
  storage_account = substr("st${local.normalized_alnum}", 0, 24)

  openai_account_name = substr("aoai-${local.normalized_dns}", 0, 64)
  openai_subdomain    = substr("${local.normalized_dns}openai", 0, 64)
  ai_project_suffix   = substr(join("", regexall("[a-zA-Z0-9-]", "${var.ai_foundry_project_name}")), 0, 64)
}
