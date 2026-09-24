variable "region" {
  type    = string
  default = "us-east-2"
}
variable "aws_profile" {
  type    = string
  default = "shc-dev-build-l"
}

# ---- Required tag set ----
variable "build_user" {
  type    = string
  default = "C5425849"
}
variable "business" {
  type    = string
  default = "SC Security and Compliance"
}
variable "description" {
  type    = string
  default = "Layer-02 instances + VPN - onboarding training (SCSEC-7956)"
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

# ---- Compute ----
variable "vpn_ami_id" {
  description = "AMI ID for the public VPN instance - confirm with John/Patryk (see notes). No default on purpose."
  type        = string
}
variable "vpn_instance_type" {
  type    = string
  default = "t3.small"
}
variable "private_instance_type" {
  type    = string
  default = "t3.micro"
}
variable "public_key_path" {
  description = "Public key to register as the EC2 key pair (reusing your onboarding ed25519)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# Lock SSH/VPN admin access to your own IP where possible.
# Find yours: curl -s https://checkip.amazonaws.com
variable "admin_cidr" {
  description = "CIDR allowed to reach SSH and the VPN admin UI on the public instance"
  type        = string
  default     = "0.0.0.0/0" # tighten to <your-ip>/32 - see notes
}




data "terraform_remote_state" "layer_00" {
  backend = "local"
  config  = { path = "../layer-00/terraform.tfstate" }
}

data "terraform_remote_state" "layer_01" {
  backend = "local"
  config  = { path = "../layer-01/terraform.tfstate" }
}

# Get the VPC CIDR without hardcoding it
data "aws_vpc" "this" {
  id = data.terraform_remote_state.layer_00.outputs.vpc_id
}

# Latest official Red Hat RHEL 9 AMI (private instance / future bastion)
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}





resource "aws_key_pair" "this" {
  key_name   = "keypair-${local.name_suffix}"
  public_key = file(pathexpand(var.public_key_path))

  tags = {
    Name = "keypair-${local.name_suffix}"
  }
}


# Public VPN instance SG - SSH + OpenVPN from admin_cidr
resource "aws_security_group" "vpn" {
  name        = "vpn-sg-${local.name_suffix}"
  description = "VPN instance - SSH and OpenVPN inbound"
  vpc_id      = data.terraform_remote_state.layer_00.outputs.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "OpenVPN tunnel (UDP)"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "OpenVPN AS web/tunnel (TCP 443)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  ingress {
    description = "OpenVPN AS admin UI (TCP 943)"
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vpn-sg-${local.name_suffix}"
  }
}

# Private instance SG - reachable only from within the VPC / via the VPN box
resource "aws_security_group" "private" {
  name        = "private-sg-${local.name_suffix}"
  description = "Private instance - SSH from VPN instance and within VPC"
  vpc_id      = data.terraform_remote_state.layer_00.outputs.vpc_id

  ingress {
    description     = "SSH from the VPN/bastion instance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }
  ingress {
    description = "SSH from within the VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private-sg-${local.name_suffix}"
  }
}



# Private instance - no public IP (becomes the bastion in 7960)
resource "aws_instance" "private" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = var.private_instance_type
  subnet_id              = data.terraform_remote_state.layer_00.outputs.private_subnet_id
  vpc_security_group_ids = [aws_security_group.private.id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = data.terraform_remote_state.layer_01.outputs.instance_profile_name

  associate_public_ip_address = false # explicit: private only

  tags = {
    Name = "private-instance-${local.name_suffix}"
  }
}

# Public VPN instance - uses the VPN AMI
resource "aws_instance" "vpn" {
  ami                    = var.vpn_ami_id
  instance_type          = var.vpn_instance_type
  subnet_id              = data.terraform_remote_state.layer_00.outputs.public_subnet_id
  vpc_security_group_ids = [aws_security_group.vpn.id]
  key_name               = aws_key_pair.this.key_name

  tags = {
    Name = "vpn-instance-${local.name_suffix}"
  }
}

# Stable public address for the VPN endpoint (matches the topology in the SCI docs,
# where the OpenVPN server sits behind a floating IP)
resource "aws_eip" "vpn" {
  instance = aws_instance.vpn.id
  domain   = "vpc"

  tags = {
    Name = "eip-vpn-${local.name_suffix}"
  }
}


region      = "us-east-2"
aws_profile = "shc-dev-build-l"

build_user   = "C5425849"
business     = "SC Security and Compliance"
description  = "Layer-02 instances + VPN - onboarding training (SCSEC-7956)"
environment  = "training"
generated_by = "terraform"
managed_by   = "terraform"
owner        = "C5425849"

vpn_ami_id = "ami-xxxxxxxxxxxx"   # <-- confirm this (see notes)
# admin_cidr = "1.2.3.4/32"       # <-- your IP; run: curl -s https://checkip.amazonaws.com
