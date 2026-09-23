provider "aws" {
  region  = var.region
  profile = var.aws_profile

 
  default_tags {
    tags = {
      BuildUser    = var.build_user
      Business     = var.business
      Description  = var.description
      Environment  = var.environment
      Generated-By = var.generated_by
      Managed-By   = var.managed_by
      Owner        = var.owner
    }
  }
}
