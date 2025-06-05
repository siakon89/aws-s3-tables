# ECR Docker image for Lambda
module "docker_image" {
  source = "terraform-aws-modules/lambda/aws//modules/docker-build"

  ecr_repo    = module.ecr.repository_name
  source_path = "${path.module}/lambdas"

  use_image_tag = true
}

module "ecr" {
  source = "terraform-aws-modules/ecr/aws"

  repository_name         = "${local.project_name}-ecr"
  repository_force_delete = true

  create_lifecycle_policy = false

  repository_lambda_read_access_arns = [module.trigger_step_function.lambda_function_arn]
}


module "trigger_step_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.20"

  function_name = "${local.project_name}-trigger-step-function"
  description   = "Lambda function to trigger Step Function when a file is uploaded to S3"

  create_package = false
  image_uri      = module.docker_image.image_uri
  package_type   = "Image"

  timeout     = 300
  memory_size = 512

  environment_variables = {
    GLUE_JOB_NAME     = aws_glue_job.csv_to_iceberg.name
    STATE_MACHINE_ARN = module.etl_state_machine.state_machine_arn
    TABLE_NAMESPACE   = aws_s3tables_namespace.iceberg_namespace.namespace
    TABLE_NAME        = local.table_name
    TABLE_BUCKET_ARN  = module.s3_tables_bucket.s3_table_bucket_arn
  }

  image_config_command = ["trigger_step_function.handler"]

  attach_policies = true
  policies = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    aws_iam_policy.lambda_glue_access.arn,
    aws_iam_policy.lambda_step_functions_policy.arn
  ]
  number_of_policies = 3

  tags = local.tags
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.raw_data_bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = module.trigger_step_function.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = module.trigger_step_function.lambda_function_arn
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${module.raw_data_bucket.s3_bucket_id}"
}

resource "aws_iam_policy" "lambda_glue_access" {
  name        = "${local.project_name}-lambda-glue-access"
  description = "Policy for Lambda to start Glue jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun"
        ]
        Resource = "arn:aws:glue:${local.region}:*:job/${aws_glue_job.csv_to_iceberg.name}"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_step_functions_policy" {
  name        = "${local.project_name}-lambda-step-functions-policy"
  description = "Policy for Lambda to start Step Functions state machine"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "states:StartExecution"
        ]
        Resource = module.etl_state_machine.state_machine_arn
      }
    ]
  })
}
