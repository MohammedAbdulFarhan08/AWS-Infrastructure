provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}


variable "region" {
  type    = string
  default = "us-east-2"
}
variable "aws_profile" {
  type    = string
  default = "shc-dev-build-l"
}

# ---- Context / tagging (null-context required set) ----
variable "build_user" {
  type    = string
  default = "C5425849"
}
variable "business" {
  type    = string
  default = "ns2"
}
variable "customer" {
  type    = string
  default = "ns2"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "owner" {
  type    = string
  default = "C5425849"
}
variable "security_boundary" {
  type    = string
  default = "cre" # <-- CONFIRM with John (prod/cre/fedciv)
}
variable "organization" {
  type    = string
  default = "ns2"
}
variable "environment_salt" {
  type    = string
  default = "a1b2c3d4" # 8 hex chars
}

# ---- Networking ----
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16" # distinct from layer-00 (10.0.0.0/16) to avoid overlap
}
variable "availability_zone" {
  type    = string
  default = "us-east-2b"
}

# ---- Key pair / access ----
variable "public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}
variable "admin_cidr" {
  type    = string
  default = "208.127.240.18/32"
}

# Reads layer-01's IAM instance profile (built earlier) via remote state
data "terraform_remote_state" "layer_01" {
  backend = "local"
  config  = { path = "../layer-01/terraform.tfstate" }
}

module "context" {
  source = "./modules/terraform-null-context"

  partition         = "aws"
  account_id        = data.aws_caller_identity.current.account_id
  region            = var.region
  build_user        = var.build_user
  managed_by        = "terraform"
  generated_by      = "terraform"
  business          = var.business
  customer          = var.customer
  environment       = var.environment
  environment_salt  = var.environment_salt
  owner             = var.owner
  security_boundary = var.security_boundary
  organization      = var.organization
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(module.context.tags, {
    Name = "vpc-${lower(var.build_user)}"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(module.context.tags, {
    Name = "igw-${lower(var.build_user)}"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(module.context.tags, {
    Name = "eip-nat-${lower(var.build_user)}"
  })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this["public"].id
  depends_on    = [aws_internet_gateway.this]

  tags = merge(module.context.tags, {
    Name = "ngw-${lower(var.build_user)}"
  })
}

locals {
  subnets = {
    public  = { cidr = "10.10.1.0/24", public = true }
    private = { cidr = "10.10.2.0/24", public = false }
  }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = each.value.public

  tags = merge(module.context.tags, {
    Name = "subnet-${each.key}-${lower(var.build_user)}"
  })
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(module.context.tags, {
    Name = "rt-public-${lower(var.build_user)}"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.this["public"].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(module.context.tags, {
    Name = "rt-private-${lower(var.build_user)}"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.this["private"].id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "vpn" {
  name        = "vpn-sg-${lower(var.build_user)}"
  description = "VPN instance - SSH and OpenVPN inbound"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = [var.admin_cidr]
  }
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(module.context.tags, {
    Name = "vpn-sg-${lower(var.build_user)}"
  })
}

resource "aws_security_group" "private" {
  name        = "private-sg-${lower(var.build_user)}"
  description = "Private instance SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SSH from VPN instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }
  ingress {
    description = "SSH from within VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(module.context.tags, {
    Name = "private-sg-${lower(var.build_user)}"
  })
}


resource "aws_key_pair" "this" {
  key_name   = "keypair-${lower(var.build_user)}"
  public_key = file(pathexpand(var.public_key_path))

  tags = merge(module.context.tags, {
    Name = "keypair-${lower(var.build_user)}"
  })
}


locals {
  instances = {
    vpn = {
      search_ami_name     = "Golden-SCS-Ubuntu-20.04-OpenVPN-V*"
      search_ami_owner_id = "274741170391" # <-- CONFIRM owner of the OpenVPN image
      instance_type       = "t3.small"
      subnet              = "public"
      sg                  = "vpn"
      public_ip           = true
      description         = "Rework VPN instance (SCSEC-7955)"
    }
    private = {
      search_ami_name     = "RHEL-9.*_HVM-*-x86_64-*"
      search_ami_owner_id = "309956199498" # Red Hat
      instance_type       = "t3.micro"
      subnet              = "private"
      sg                  = "private"
      public_ip           = false
      description         = "Rework private instance (SCSEC-7955)"
    }
  }
}

# Per-instance context (legacy sub-module) - unique Name/tags per instance,
# inheriting the base context. Mirrors example-root pattern.
module "instance_context" {
  source   = "./modules/terraform-null-context/modules/legacy"
  for_each = local.instances

  context       = module.context.context
  custom_values = module.context.custom_values

  additional_tags = {
    Name        = "${each.key}-instance-${lower(var.build_user)}"
    Description = each.value.description
    ProductName = "training"
  }
}

module "instance" {
  source   = "./modules/aws-instance"
  for_each = local.instances

  search_ami_name     = each.value.search_ami_name
  search_ami_owner_id = each.value.search_ami_owner_id

  aws_region           = var.region
  instance_type        = each.value.instance_type
  ec2_key              = aws_key_pair.this.key_name
  subnet_id            = aws_subnet.this[each.value.subnet].id
  security_group_ids   = [each.value.sg == "vpn" ? aws_security_group.vpn.id : aws_security_group.private.id]
  iam_instance_profile = each.key == "private" ? data.terraform_remote_state.layer_01.outputs.instance_profile_name : null

  associate_public_ip_address = each.value.public_ip

  module_dependency = join(",", [])
  context           = module.instance_context[each.key].context
}


output "vpc_id" {
  value = aws_vpc.this.id
}
output "subnet_ids" {
  value = { for k, s in aws_subnet.this : k => s.id }
}
output "vpn_security_group_id" {
  value = aws_security_group.vpn.id
}
output "private_security_group_id" {
  value = aws_security_group.private.id
}
output "instance_ids" {
  value = { for k, m in module.instance : k => m.id }
}


region      = "us-east-2"
aws_profile = "shc-dev-build-l"
