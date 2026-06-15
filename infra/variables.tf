variable "name_prefix" {
  description = "Name prefix used for Azure resources."
  type        = string
  default     = "wordgame"
}

variable "environment" {
  description = "Environment suffix used in resource names."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for regional resources."
  type        = string
  default     = "centralus"
}

variable "vnet_address_space" {
  description = "Address space for the standalone virtual network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "waf_subnet_address_prefix" {
  description = "Subnet prefix for the public WAF container app environment."
  type        = string
  default     = "10.0.0.0/23"
}

variable "aca_subnet_address_prefix" {
  description = "Subnet prefix for the internal Container Apps environment."
  type        = string
  default     = "10.0.8.0/21"
}

variable "private_endpoints_subnet_address_prefix" {
  description = "Subnet prefix for private endpoints."
  type        = string
  default     = "10.0.4.0/24"
}

variable "management_subnet_address_prefix" {
  description = "Subnet prefix reserved for future management resources."
  type        = string
  default     = "10.0.5.0/24"
}

variable "container_port" {
  description = "Default application container port."
  type        = number
  default     = 8080
}

variable "placeholder_image" {
  description = "Public bootstrap image used for initial Container App creation before app images are built."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "acr_sku" {
  description = "Azure Container Registry SKU."
  type        = string
  default     = "Premium"
}

variable "waf_image" {
  description = "Public WAF image that fronts the internal web app."
  type        = string
  default     = "owasp/modsecurity-crs:nginx-alpine"
}

variable "cosmos_offer_type" {
  description = "Cosmos DB offer type."
  type        = string
  default     = "Standard"
}

variable "cosmos_consistency_level" {
  description = "Cosmos DB consistency level."
  type        = string
  default     = "Session"
}

variable "cosmos_database_name" {
  description = "Cosmos SQL database name."
  type        = string
  default     = "wordgame-db"
}

variable "cosmos_container_name" {
  description = "Cosmos SQL container name."
  type        = string
  default     = "game-events"
}

variable "cosmos_partition_key_path" {
  description = "Cosmos SQL container partition key path."
  type        = string
  default     = "/gameId"
}

variable "openai_sku_name" {
  description = "Azure OpenAI SKU."
  type        = string
  default     = "S0"
}

variable "openai_model_name" {
  description = "Placeholder Azure OpenAI model name for deployment."
  type        = string
  default     = "gpt-4o-mini"
}

variable "openai_model_version" {
  description = "Placeholder Azure OpenAI model version."
  type        = string
  default     = "2024-07-18"
}

variable "openai_deployment_name" {
  description = "Placeholder Azure OpenAI deployment name."
  type        = string
  default     = "chat-default"
}

variable "openai_deployment_sku" {
  description = "Azure OpenAI deployment SKU name."
  type        = string
  default     = "GlobalStandard"
}

variable "ai_foundry_project_name" {
  description = "Placeholder AI Foundry project name."
  type        = string
  default     = "wordgame-project"
}

variable "enable_role_assignments" {
  description = "Enable role assignment resources that require User Access Administrator or Owner."
  type        = bool
  default     = false
}

variable "enable_foundry_resources" {
  description = "Enable preview Foundry/OpenAI deployment resources."
  type        = bool
  default     = false
}

variable "enable_openai_resources" {
  description = "Enable Azure OpenAI account and dependent resources."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default = {
    workload = "word-game"
    managed  = "terraform"
  }
}
