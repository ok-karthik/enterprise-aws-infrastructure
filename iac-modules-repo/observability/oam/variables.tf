variable "mode" {
  description = "sink = the monitoring (observability) account's side: receives data from the organization. link = a source account's side: sends its metrics, logs and traces to the sink."
  type        = string

  validation {
    condition     = contains(["sink", "link"], var.mode)
    error_message = "mode must be sink or link."
  }
}

variable "organization_id" {
  description = "sink mode: ID of the AWS Organization (o-xxxxxxxxxx). The sink policy lets only accounts of this organization link to it."
  type        = string
  default     = ""

  validation {
    condition     = var.mode != "sink" || (can(regex("^o-[a-z0-9]{10,32}$", var.organization_id)) && !can(regex("^o-0+$", var.organization_id)))
    error_message = "sink mode needs a real organization_id (o-...), not empty or the 0000 placeholder."
  }
}

variable "sink_name" {
  description = "sink mode: name of the sink (letters, digits, hyphens; unique per account and region)."
  type        = string
  default     = "platform-observability"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,49}$", var.sink_name))
    error_message = "sink_name must be 1-50 characters: letters, digits, hyphen or underscore."
  }
}

variable "sink_arn" {
  description = "link mode: ARN of the sink in the observability account (same region as this account's link). Also readable from the sink stack's sink_arn output."
  type        = string
  default     = ""

  validation {
    condition     = var.mode != "link" || can(regex("^arn:aws[a-z-]*:oam:[a-z0-9-]+:[0-9]{12}:sink/[a-z0-9-]+$", var.sink_arn))
    error_message = "link mode needs sink_arn, an OAM sink ARN (arn:aws:oam:<region>:<account>:sink/<id>)."
  }
}

variable "resource_types" {
  description = "What is shared. Metrics and logs by default; add AWS::XRay::Trace for traces."
  type        = list(string)
  default     = ["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup"]

  validation {
    condition = length(var.resource_types) > 0 && alltrue([
      for t in var.resource_types :
      contains(["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup", "AWS::XRay::Trace", "AWS::ApplicationInsights::Application", "AWS::InternetMonitor::Monitor"], t)
    ])
    error_message = "resource_types must be a non-empty list of supported OAM resource types."
  }
}

variable "label_template" {
  description = "link mode: how this account is labelled in the monitoring account's console. $AccountName is the account's name."
  type        = string
  default     = "$AccountName"
}

variable "enable_prometheus" {
  description = "sink mode, optional: create an Amazon Managed Service for Prometheus workspace in the observability account. Costs per ingested sample. Managed Grafana is not created here: it needs IAM Identity Center wiring and is a separate decision."
  type        = bool
  default     = false
}

variable "prometheus_alias" {
  description = "Alias of the Prometheus workspace when enable_prometheus is true."
  type        = string
  default     = "platform"
}

variable "tags" {
  description = "Extra tags"
  type        = map(string)
  default     = {}
}
