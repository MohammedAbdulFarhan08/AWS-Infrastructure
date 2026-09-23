locals {
  # Naming convention: <resource>-<c-user id>, e.g. vpc-c5425849
  name_suffix = lower(var.build_user)
}
