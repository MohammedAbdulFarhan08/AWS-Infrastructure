output "vpc_id" {
  value = aws_vpc.this.id
}
output "public_subnet_id" {
  value = aws_subnet.public.id
}
output "private_subnet_id" {
  value = aws_subnet.private.id
}
output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}
output "nat_gateway_id" {
  value = aws_nat_gateway.this.id
}
output "ingress_security_group_id" {
  value = aws_security_group.ingress.id
}
output "egress_security_group_id" {
  value = aws_security_group.egress.id
}


output "iam_role_name" {
  value = aws_iam_role.this.name
}
output "iam_role_arn" {
  value = aws_iam_role.this.arn
}
output "instance_profile_name" {
  value = aws_iam_instance_profile.this.name
}
output "instance_profile_arn" {
  value = aws_iam_instance_profile.this.arn
}
