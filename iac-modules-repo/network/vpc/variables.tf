variable "name" {
  description = "Name to be used on all resources as prefix"
  type        = string
}

variable "cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "A list of availability zones names or ids in the region"
  type        = list(string)
}

variable "private_subnets" {
  description = "A list of private subnets inside the VPC"
  type        = list(string)
}

variable "public_subnets" {
  description = "A list of public subnets inside the VPC"
  type        = list(string)
}

variable "database_subnets" {
  description = "A list of database subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Should be true if you want to provision NAT Gateways for each of your private networks"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway across all of your private networks"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster to tag subnets for"
  type        = string
  default     = ""
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

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
