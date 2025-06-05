module "s3_tables_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws//modules/table-bucket"
  version = "~> 4.10"

  table_bucket_name = local.s3_tables_bucket_name
  encryption_configuration = {
    kms_key_arn   = module.kms.key_arn
    sse_algorithm = "aws:kms"
  }

  maintenance_configuration = {
    iceberg_unreferenced_file_removal = {
      status = "enabled"

      settings = {
        non_current_days  = 7
        unreferenced_days = 3
      }
    }
  }

  create_table_bucket_policy = true
  table_bucket_policy        = data.aws_iam_policy_document.s3_tables_bucket_policy.json
}

data "aws_iam_policy_document" "s3_tables_bucket_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.current_account.account_id]
    }

    actions = [
      "s3tables:GetTableData",
      "s3tables:GetTableMetadataLocation"
    ]
  }
}

# S3 Tables Namespace - requires a table bucket
resource "aws_s3tables_namespace" "iceberg_namespace" {
  namespace        = local.namespace_name
  table_bucket_arn = module.s3_tables_bucket.s3_table_bucket_arn
}

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  description             = "Key example for s3 table buckets"
  deletion_window_in_days = 7

  key_statements = [
    {
      sid = "s3TablesMaintenancePolicy"
      actions = [
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ]
      resources = ["*"]

      principals = [
        {
          type        = "Service"
          identifiers = ["maintenance.s3tables.amazonaws.com"]
        }
      ]

      conditions = [
        {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values = [
            data.aws_caller_identity.current_account.account_id,
          ]
        },
        {
          test     = "StringLike"
          variable = "kms:EncryptionContext:aws:s3:arn"
          values = [
            "arn:aws:s3tables:${data.aws_region.current_region.name}:${data.aws_caller_identity.current_account.account_id}:bucket/${local.s3_tables_bucket_name}/table/*"
          ]
        }
      ]
    }
  ]
}

# Uncomment this after the first successfull apply from Terraform and 
# after you have enabled Integration in Table buckets with Analytics services and
# after you have enabled Lake Formation with you as an Admin

# resource "aws_lakeformation_permissions" "data_location" {
#   principal   = aws_iam_role.glue_job_role.arn
#   permissions = ["DATA_LOCATION_ACCESS"]

#   data_location {
#     arn = module.s3_tables_bucket.s3_table_bucket_arn
#   }
# }

