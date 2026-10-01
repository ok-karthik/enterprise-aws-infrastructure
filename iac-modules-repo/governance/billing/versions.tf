terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
      # Billing Data Exports only exists in us-east-1 and the resource has no region argument, so the caller
      # passes a second provider configuration for it (the leaf generates it; the region in the root provider stays).
      configuration_aliases = [aws.us_east_1]
    }
  }
}
