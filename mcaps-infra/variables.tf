variable "spoke_subscription_id" {
  type        = string
  sensitive   = true
  description = "Azure subscription ID for the spoke."
}

variable "hub_subscription_id" {
  type        = string
  sensitive   = true
  description = "Azure subscription ID for the hub."
}

variable "hub_resource_group_name" {
  type        = string
  description = "Hub resource group name."
}

variable "hub_vnet_name" {
  type        = string
  description = "Hub VNet name."
}

variable "hub_law_name" {
  type        = string
  description = "Hub Log Analytics workspace name."
}

variable "hub_ampls_name" {
  type        = string
  description = "Hub Azure Monitor Private Link Scope name."
}

variable "lab_prefix" {
  type        = string
  description = "Shared lab prefix used in Azure resource names."
}

variable "spoke_short_name" {
  type        = string
  description = "Short spoke name used in derived resource names."
  default     = "infra"
}

variable "spoke_type" {
  type        = string
  description = "Spoke workload type."
  default     = "generic"

  validation {
    condition     = contains(["generic", "aks", "ml"], var.spoke_type)
    error_message = "spoke_type must be one of: generic, aks, ml."
  }
}

variable "spoke_region" {
  type        = string
  description = "Azure region for the spoke."
  default     = "centralus"
}

variable "cidr_registry_repo" {
  type        = string
  description = "GitHub repo URL that contains cidr.yaml."
  default     = "https://github.com/hoopdad/mikeo-hub"
}

variable "spoke_vnet_address_space" {
  type        = list(string)
  description = "CIDR blocks assigned to the spoke VNet."
}

variable "workload_subnet_cidr" {
  type        = string
  description = "CIDR for the reserved workload/management subnet."
}

variable "pep_subnet_cidr" {
  type        = string
  description = "CIDR for the private endpoint subnet."
}

variable "private_dns_zone_names" {
  type        = list(string)
  description = "Private DNS zones present in the hub and consumed by the spoke private endpoints. Zones must exist in the hub before apply (see _hub-todo)."
}

variable "aca_subnet_cidr" {
  type        = string
  description = "CIDR for the internal Container Apps environment subnet (delegated, /27 minimum)."
}

variable "waf_subnet_cidr" {
  type        = string
  description = "CIDR for the private WAF Container Apps environment subnet (delegated, /27 minimum)."
}

variable "container_port" {
  type        = number
  description = "Default application container port."
  default     = 8080
}

variable "placeholder_image" {
  type        = string
  description = "Public bootstrap image used for initial Container App creation before app images are built."
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "waf_image" {
  type        = string
  description = "WAF image used for initial WAF Container App creation."
  default     = "owasp/modsecurity-crs:nginx-alpine"
}

variable "acr_sku" {
  type        = string
  description = "Azure Container Registry SKU."
  default     = "Premium"
}

variable "cosmos_consistency_level" {
  type        = string
  description = "Cosmos DB consistency level."
  default     = "Session"
}

variable "cosmos_database_name" {
  type        = string
  description = "Cosmos SQL database name."
  default     = "wordgame-db"
}

variable "cosmos_container_name" {
  type        = string
  description = "Cosmos SQL container name."
  default     = "game-events"
}

variable "cosmos_partition_key_path" {
  type        = string
  description = "Cosmos SQL container partition key path."
  default     = "/gameId"
}

variable "cosmos_container_throughput" {
  type        = number
  description = "Manual RU/s throughput for the Cosmos SQL database."
  default     = 400
}

variable "openai_sku_name" {
  type        = string
  description = "Azure OpenAI SKU."
  default     = "S0"
}

variable "openai_model_name" {
  type        = string
  description = "Placeholder Azure OpenAI model name for deployment."
  default     = "gpt-4o-mini"
}

variable "openai_model_version" {
  type        = string
  description = "Placeholder Azure OpenAI model version."
  default     = "2024-07-18"
}

variable "openai_deployment_name" {
  type        = string
  description = "Placeholder Azure OpenAI deployment name."
  default     = "chat-default"
}

variable "openai_deployment_sku" {
  type        = string
  description = "Azure OpenAI deployment SKU name."
  default     = "GlobalStandard"
}

variable "ai_foundry_project_name" {
  type        = string
  description = "Placeholder AI Foundry project name."
  default     = "wordgame-project"
}

variable "enable_role_assignments" {
  type        = bool
  description = "Enable role assignments that require User Access Administrator or Owner."
  default     = false
}

variable "enable_openai_resources" {
  type        = bool
  description = "Enable Azure OpenAI account and dependent resources."
  default     = false
}

variable "enable_foundry_resources" {
  type        = bool
  description = "Enable preview Foundry/OpenAI deployment resources."
  default     = false
}

variable "enable_storage" {
  type        = bool
  description = "Enable an optional artifacts storage account with a blob private endpoint."
  default     = false
}

variable "enable_self_hosted_runner" {
  type        = bool
  description = "Enable a private self-hosted GitHub Actions runner VM in the workload subnet."
  default     = true
}

variable "runner_vm_size" {
  type        = string
  description = "Azure VM size for the self-hosted runner."
  default     = "Standard_D2s_v4"
}

variable "runner_label" {
  type        = string
  description = "Base label used when registering ephemeral self-hosted runners."
  default     = "wordgame-spoke"
}

variable "github_runner_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token for registering the self-hosted runner (requires 'admin:org' scope)."
  default     = ""
}

variable "use_remote_gateways" {
  type        = bool
  description = "Allow the spoke to use the hub gateway."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to merge onto spoke resources."
  default     = {}
}
