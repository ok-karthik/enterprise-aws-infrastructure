variable "cluster_name" {
  description = "Name of the EKS cluster for Pod Identity associations"
  type        = string
}

variable "workload_identities" {
  description = "Map of (namespace, service account) pairs to IAM role ARNs using EKS Pod Identity"
  type = map(object({
    namespace            = string
    service_account_name = string
    role_arn             = string
  }))
  default = {}
}

variable "oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL. Required only if using the IRSA fallback path"
  type        = string
  default     = ""
}

variable "irsa_roles" {
  description = "Map of (namespace, service account) pairs needing the IRSA fallback instead of Pod Identity"
  type = map(object({
    namespace            = string
    service_account_name = string
    policy_arns          = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
