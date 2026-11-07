terraform {
  required_version = ">= 1.7" # removed block

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.72.0"
    }
    buildkit = {
      source  = "cruxstack/buildkit"
      version = ">= 0.0.2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9.1"
    }
  }
}
