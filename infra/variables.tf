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

variable "container_port" {
  description = "Default application container port."
  type        = number
  default     = 8080
}

variable "acr_sku" {
  description = "Azure Container Registry SKU."
  type        = string
  default     = "Basic"
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

variable "ai_foundry_project_name" {
  description = "Placeholder AI Foundry project name."
  type        = string
  default     = "wordgame-project"
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default = {
    workload = "word-game"
    managed  = "terraform"
  }
}
