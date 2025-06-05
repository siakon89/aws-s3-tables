# Upload the S3 Tables Iceberg connector JAR
resource "aws_s3_object" "s3_tables_connector" {
  bucket = module.artifacts_bucket.s3_bucket_id
  key    = "jars/s3-tables-catalog-for-iceberg-runtime-0.1.5.jar"
  source = "${path.module}/jars/s3-tables-catalog-for-iceberg-runtime-0.1.5.jar"
  etag   = filemd5("${path.module}/jars/s3-tables-catalog-for-iceberg-runtime-0.1.5.jar")
}

# Upload the Glue job script to S3
resource "aws_s3_object" "glue_job_script" {
  depends_on = [aws_s3_object.s3_tables_connector]
  bucket     = module.artifacts_bucket.s3_bucket_id
  key        = "scripts/csv_to_iceberg.py"
  source     = "${path.module}/scripts/csv_to_iceberg.py"
  etag       = filemd5("${path.module}/scripts/csv_to_iceberg.py")
}

# Glue job definition
resource "aws_glue_job" "csv_to_iceberg" {
  depends_on = [aws_s3_object.glue_job_script]
  name       = "${local.project_name}-csv-to-iceberg"
  role_arn   = aws_iam_role.glue_job_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${module.artifacts_bucket.s3_bucket_id}/${aws_s3_object.glue_job_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "s3://${module.raw_data_bucket.s3_bucket_id}/temp/"
    "--extra-jars"                       = "s3://${module.artifacts_bucket.s3_bucket_id}/jars/s3-tables-catalog-for-iceberg-runtime-0.1.5.jar"
  }

  execution_property {
    max_concurrent_runs = 2
  }

  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15
}

resource "aws_iam_role" "glue_job_role" {
  name = "${local.project_name}-glue-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_policy" "glue_s3_access" {
  name        = "${local.project_name}-glue-s3-access"
  description = "Policy for Glue job to access S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${module.raw_data_bucket.s3_bucket_id}",
          "arn:aws:s3:::${module.raw_data_bucket.s3_bucket_id}/*",
          "arn:aws:s3:::${module.artifacts_bucket.s3_bucket_id}",
          "arn:aws:s3:::${module.artifacts_bucket.s3_bucket_id}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "glue_s3_tables_access" {
  name        = "${local.project_name}-glue-s3-tables-access"
  description = "Policy for Glue job to access S3 Tables"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3tables:PutTableData",
          "s3tables:GetTableData",
          "s3tables:GetTableMetadataLocation",
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetTablePolicy",
          "s3tables:GetNamespace",
          "s3tables:GetBucket",
          "s3tables:ListNamespaces",
          "s3tables:ListTables",
          "s3tables:CreateTable",
          "s3tables:GetTableBucket"
        ]
        Resource = [
          "arn:aws:s3tables:${local.region}:${data.aws_caller_identity.current_account.account_id}:bucket/${local.s3_tables_bucket_name}",
          "arn:aws:s3tables:${local.region}:${data.aws_caller_identity.current_account.account_id}:bucket/${local.s3_tables_bucket_name}/table/*",
          "arn:aws:s3tables:${local.region}:${data.aws_caller_identity.current_account.account_id}:bucket/${local.s3_tables_bucket_name}/namespace/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = [
          module.kms.key_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetObjectVersion",
          "s3:ListBucketVersions"
        ]
        Resource = [
          "arn:aws:s3:::${local.s3_tables_bucket_name}",
          "arn:aws:s3:::${local.s3_tables_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_access" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_s3_access.arn
}

resource "aws_iam_role_policy_attachment" "glue_s3_tables_access" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_s3_tables_access.arn
}

resource "aws_iam_policy" "glue_lake_formation_access" {
  name        = "${local.project_name}-glue-lake-formation-access"
  description = "Policy for Glue job to access Lake Formation"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess",
          "lakeformation:ListPermissions",
          "lakeformation:GetResourceLinks",
          "lakeformation:GetTableObjects",
          "lakeformation:GetTableObjects",
          "lakeformation:UpdateTableObjects"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_lake_formation_access" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_lake_formation_access.arn
}
