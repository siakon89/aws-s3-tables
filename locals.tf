locals {
  # Project settings
  project_name = "<your-project-name>"
  environment  = "dev"
  region       = "eu-central-1"

  # Resource naming
  name_prefix = "${local.project_name}-${local.environment}"

  # Common tags
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }

  # S3 bucket configuration
  raw_data_bucket_name = "${local.name_prefix}-raw-data"

  # S3 Tables configuration
  s3_tables_bucket_name = "${local.name_prefix}-tables-bucket"
  namespace_name        = "demodb"
  table_name            = "titanic"

  # Iceberg table configuration
  table_format = "ICEBERG"
}
