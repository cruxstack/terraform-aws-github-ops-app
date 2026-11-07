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

    # transitional: only for the `removed` block of the pre-buildkit
    # module.bot_artifact, whose resources are still in the state of anyone
    # upgrading from v0.x
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.8.1"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.3.2"
    }
  }
}
