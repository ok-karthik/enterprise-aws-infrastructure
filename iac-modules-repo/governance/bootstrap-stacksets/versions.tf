terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0" # stack_set_instance_region; the plain `region` argument is deprecated
    }
  }
}
