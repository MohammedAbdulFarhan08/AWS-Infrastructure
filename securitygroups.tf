# Ingress SG - inbound SSH from within the VPC
resource "aws_security_group" "ingress" {
  name        = "sg-ingress-${local.name_suffix}"
  description = "Ingress SG - allow SSH from within the VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from within VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-ingress-${local.name_suffix}"
  }
}

# Egress SG - all outbound
resource "aws_security_group" "egress" {
  name        = "sg-egress-${local.name_suffix}"
  description = "Egress SG - allow all outbound"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-egress-${local.name_suffix}"
  }
}
