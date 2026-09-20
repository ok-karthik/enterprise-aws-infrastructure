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
  description = "Indicates whether or not the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "api_allowed_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = []
}

variable "env" {
  description = "Target environment for naming and discovery contract (e.g. dev, prod)"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region for naming and discovery contract (e.g. eu-central-1)"
  type        = string
  default     = ""
}

variable "publish_ssm_parameters" {
  description = "Whether to publish discovery contract parameters to SSM Parameter Store"
  type        = bool
  default     = false
}
