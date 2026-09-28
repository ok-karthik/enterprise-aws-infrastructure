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
  default     = "prod"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource"
  default     = {}
}

variable "mode" {
  type        = string
  description = <<-EOT
    standalone       a normal Aurora PostgreSQL cluster in this region (password managed by Secrets Manager).
    global_primary   the writer cluster of an Aurora Global Database; also creates the global cluster.
    global_secondary a read-only cluster in another region, attached to global_cluster_identifier. Apply the primary first.
  EOT
  default     = "standalone"

  validation {
    condition     = contains(["standalone", "global_primary", "global_secondary"], var.mode)
    error_message = "mode must be standalone, global_primary or global_secondary."
  }
}

variable "global_cluster_identifier" {
  type        = string
  description = "global_secondary only: the global cluster to join (the global_cluster_identifier output of the primary)."
  default     = ""

  validation {
    condition     = var.mode != "global_secondary" || var.global_cluster_identifier != ""
    error_message = "global_cluster_identifier is required when mode = global_secondary."
  }
}

variable "source_region" {
  type        = string
  description = "global_secondary only: the primary cluster's region. AWS needs it to copy the encrypted storage across regions."
  default     = ""

  validation {
    condition     = var.mode != "global_secondary" || var.source_region != ""
    error_message = "source_region is required when mode = global_secondary."
  }
}

variable "kms_key_id" {
  type        = string
  description = "Customer-managed KMS key ARN in THIS region for the cluster storage. Required for global_secondary (a key in the secondary region), recommended for the primary."
  default     = ""

  validation {
    condition     = var.mode != "global_secondary" || var.kms_key_id != ""
    error_message = "kms_key_id is required when mode = global_secondary, because a replica cannot use the primary region's key."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC to place the cluster security group in."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for the DB subnet group (at least two, in different AZs; use the database subnets)."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Aurora needs at least two subnets in different availability zones."
  }
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach PostgreSQL (5432). Default is the private supernet, never the internet."
  default     = ["10.0.0.0/8"]

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "allowed_cidrs must not contain 0.0.0.0/0."
  }
}

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version. Must match between the global cluster, the primary and every secondary."
  default     = "16.6"
}

variable "instance_class" {
  type        = string
  description = "Instance class. Aurora Global Database does not support the burstable db.t* classes."
  default     = "db.r6g.large"

  validation {
    condition     = var.mode == "standalone" || !startswith(var.instance_class, "db.t")
    error_message = "Aurora Global Database does not support burstable (db.t*) instance classes."
  }
}

variable "instance_count" {
  type        = number
  description = "Number of instances in this cluster (1 writer + readers). 2 or more spreads across AZs."
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 15
    error_message = "instance_count must be between 1 and 15."
  }
}

variable "backup_retention_days" {
  type        = number
  description = "Automated backup retention in days."
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 7
    error_message = "Keep at least 7 days of backups for a production database."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Block deletion of the cluster (and global cluster) until turned off in a separate change."
  default     = true
}
