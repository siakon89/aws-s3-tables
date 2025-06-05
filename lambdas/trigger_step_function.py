import json
import boto3
import os
import urllib.parse
from datetime import datetime

# Initialize AWS clients
step_functions = boto3.client('stepfunctions')

def handler(event, context):
    
    # Get the Step Functions state machine ARN from environment variable
    state_machine_arn = os.environ.get('STATE_MACHINE_ARN')
    table_namespace = os.environ.get('TABLE_NAMESPACE')
    table_name = os.environ.get('TABLE_NAME')
    table_bucket_arn = os.environ.get('TABLE_BUCKET_ARN')
    
    if not state_machine_arn:
        raise Exception("STATE_MACHINE_ARN environment variable is not set")
    

    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])  
    print(f"File uploaded: s3://{bucket}/{key}")
        
    # Prepare input and output paths for the state machine
    input_path = f"s3://{bucket}/{key}"
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        
    print(f"Starting Step Functions state machine: {state_machine_arn}")
    print(f"Input path: {input_path}")
        
    # Prepare input for the state machine
    state_machine_input = {
        "source_s3_path": input_path,
        "table_namespace": table_namespace,
        "table_name": table_name,
        "table_bucket_arn": table_bucket_arn
    }
        
    # Start the state machine execution
    response = step_functions.start_execution(
        stateMachineArn=state_machine_arn,
        name=f"ETL-{timestamp}",
        input=json.dumps(state_machine_input)
    )
        
    execution_arn = response['executionArn']
    print(f"Step Functions state machine started successfully. Execution ARN: {execution_arn}")
        
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Step Functions state machine triggered successfully',
            'executionArn': execution_arn
        })
    }