variable "cluster_name" {
  description = "Name of the EKS cluster to grant access entries for"
  type        = string
  default     = ""
}

variable "team_access" {
  description = "Map of (team, tier) access configurations with principal ARN and kubernetes groups"
  type = map(object({
    principal_arn = string
    k8s_groups    = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
