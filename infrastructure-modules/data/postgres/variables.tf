variable "team_name" {
  type        = string
  description = "Team or tenant that owns this database"
}

variable "app_name" {
  type        = string
  description = "Application the database belongs to"
}

variable "env" {
  type        = string
  description = "Target environment (dev, staging, prod)"
  default     = "dev"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource, supplied by the scaffolder"
  default     = {}
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to place the database security group in. Empty means no security group is created."
  default     = ""
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the DB subnet group. Empty means none is created."
  default     = []
}

variable "engine_version" {
  type        = string
  description = "Major PostgreSQL engine version"
  default     = "16"
}

variable "instance_class" {
  type        = string
  description = "RDS instance class size"
  default     = "db.t3.micro"
}

variable "backup_retention_days" {
  type        = number
  description = "Automated backup retention period in days"
  default     = 7
}
