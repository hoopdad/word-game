# Remote state backend.
#
# Configuration is intentionally partial: storage account name, container,
# resource group and key are supplied at init time via -backend-config flags
# (see .github/workflows/cd.yml and scripts/bootstrap-tfstate.sh) so that no
# subscription-specific values are committed to source control.
#
# Local validation runs with `terraform init -backend=false` and never touches
# this backend.
terraform {
  backend "azurerm" {
    use_oidc = true
  }
}
