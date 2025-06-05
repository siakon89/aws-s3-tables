module "artifacts_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.8"

  bucket = "${local.project_name}-glue-artifacts-${local.environment}"

  force_destroy = true
  acl           = "private"

  # Add ownership controls
  control_object_ownership = true
  object_ownership         = "ObjectWriter"


  tags = local.tags
}

module "raw_data_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.10"

  bucket = local.raw_data_bucket_name

  force_destroy = true
  acl           = "private"

  # Add ownership controls
  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  tags = local.tags
}
