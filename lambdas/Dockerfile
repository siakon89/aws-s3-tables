FROM public.ecr.aws/lambda/python:3.12

# Copy requirements.txt
COPY requirements.txt ${LAMBDA_TASK_ROOT}

# Install the dependencies
RUN pip install -r requirements.txt

# Copy function code
COPY trigger_step_function.py ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler
CMD [ "trigger_step_function.handler" ]