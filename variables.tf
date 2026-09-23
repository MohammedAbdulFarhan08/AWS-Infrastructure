variable "region" {
  description = "AWS region for all layer-00 resources"
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Local saml2aws profile to authenticate with"
  type        = string
  default     = "shc-dev-build-l"
}

# ---- Required tag set ----
variable "build_user" {
  description = "I/C number of the engineer running this (BuildUser tag)"
  type        = string
  default     = "C5425849"
}
variable "business" {
  type    = string
  default = "SC Security and Compliance"
}
variable "description" {
  type    = string
  default = "Layer-00 networking foundation - onboarding training (SCSEC-7958)"
}
variable "environment" {
  type    = string
  default = "training"
}
variable "generated_by" {
  type    = string
  default = "terraform"
}
variable "managed_by" {
  type    = string
  default = "terraform"
}
variable "owner" {
  type    = string
  default = "C5425849"
}

# ---- Networking ----
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}
variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}
variable "availability_zone" {
  type    = string
  default = "us-east-2a"
}
