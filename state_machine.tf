# Step Functions state machine definition
module "etl_state_machine" {
  source  = "terraform-aws-modules/step-functions/aws"
  version = "~> 4.2.1"

  name = "${local.project_name}-etl-workflow"

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.step_functions_glue_policy.json

  definition = jsonencode({
    Comment = "ETL workflow to process CSV to Iceberg and crawl the data",
    StartAt = "StartGlueJob",
    States = {
      "StartGlueJob" = {
        Type     = "Task",
        Resource = "arn:aws:states:::glue:startJobRun.sync",
        Parameters = {
          JobName = aws_glue_job.csv_to_iceberg.name,
          Arguments = {
            "--source_s3_path.$"   = "$.source_s3_path",
            "--table_namespace.$"  = "$.table_namespace",
            "--table_name.$"       = "$.table_name",
            "--table_bucket_arn.$" = "$.table_bucket_arn"
          }
        },
        ResultPath = "$.glueJobResult",
        End        = true
      }
    }
  })
}

data "aws_iam_policy_document" "step_functions_glue_policy" {
  statement {
    effect = "Allow"
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun"
    ]
    resources = [
      "arn:aws:glue:${local.region}:*:job/${aws_glue_job.csv_to_iceberg.name}"
    ]
  }
}
