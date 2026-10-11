variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to use"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "A list of subnet IDs where the EKS nodes will be deployed"
  type        = list(string)
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 1
}

variable "instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["t4g.small", "t4g.medium"]
}

variable "ami_type" {
  description = "AMI type of the node group. The default is the Graviton (ARM) AL2023 image to match the default instance types; an x86 AMI on t4g/m7g/... instances cannot launch, and a mix of Graviton and x86 types is rejected."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"

  validation {
    # Graviton = a1 or a family ending in g (t4g, m7g, c7gn, ...). All Graviton needs ARM_64, none needs non-ARM, a mix is rejected.
    condition = (
      alltrue([for t in var.instance_types : can(regex("^([a-z]+[0-9]+g[a-z]*|a1)\\.", t))])
      ? strcontains(var.ami_type, "ARM_64")
      : (
        !anytrue([for t in var.instance_types : can(regex("^([a-z]+[0-9]+g[a-z]*|a1)\\.", t))])
        && !strcontains(var.ami_type, "ARM_64")
      )
    )
    error_message = "ami_type (${var.ami_type}) does not match instance_types (${join(", ", var.instance_types)}): all Graviton types (a1, t4g, m7g, c7gn, ...) need an ARM_64 AMI type, all other types need a non-ARM one, and the two cannot be mixed in one node group."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_karpenter" {
  description = "Whether to provision Karpenter AWS prerequisites (IAM roles, SQS queue, EventBridge rules)"
  type        = bool
  default     = true
}

variable "cluster_addons" {
  description = "Map of cluster addons to enable"
  type        = any
  default     = {}
}

variable "node_security_group_tags" {
  description = "Additional tags for the node security group"
  type        = map(string)
  default     = {}
}

variable "cluster_endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled. Defaults to false (private endpoint only). When true, api_allowed_cidrs must be non-empty."
  type        = bool
  default     = false
}

variable "api_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Required (non-empty) when cluster_endpoint_public_access is true; ignored otherwise."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.cluster_endpoint_public_access || length(var.api_allowed_cidrs) > 0
    error_message = "cluster_endpoint_public_access is true but api_allowed_cidrs is empty. Provide explicit CIDRs (never fall back to 0.0.0.0/0) or set cluster_endpoint_public_access = false."
  }
}

variable "scale_schedule" {
  description = "Optional working-hours schedule for the node group (dev). Sets DESIRED size only (upstream ignores desired_size drift), so min_size must be 0. null = always on. Scales only the managed node group, not nodes Karpenter launched."
  type = object({
    timezone   = optional(string, "Europe/Berlin")
    down_cron  = optional(string, "cron(0 19 ? * MON-FRI *)")
    up_cron    = optional(string, "cron(0 7 ? * MON-FRI *)")
    up_desired = optional(number, 1)
  })
  default = null

  validation {
    condition     = var.scale_schedule == null || var.min_size == 0
    error_message = "scale_schedule needs min_size = 0, or the scale-down can't go below min."
  }
}
