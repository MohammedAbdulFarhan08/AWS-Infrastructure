terraform {
  required_version = "= 1.5.7" # BSL cap - do not go 1.6.0+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state for training
  backend "local" {
    path = "terraform.tfstate"
  }
}
