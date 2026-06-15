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
  description = "CIDR for the workload subnet."
}

variable "pep_subnet_cidr" {
  type        = string
  description = "CIDR for the private endpoint subnet."
}

variable "private_dns_zone_names" {
  type        = list(string)
  description = "Private DNS zones already present in the hub and linked from the spoke."
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
