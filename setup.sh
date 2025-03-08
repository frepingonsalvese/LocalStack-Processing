#!/bin/bash

# Create S3 bucket
echo "Creating S3 bucket..."
awslocal s3 mb s3://csv-bucket

# Create DynamoDB table
echo "Creating DynamoDB table..."
awslocal dynamodb create-table \
    --table-name csv-metadata \
    --attribute-definitions AttributeName=filename,AttributeType=S \
    --key-schema AttributeName=filename,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST

# Create IAM role for Lambda
echo "Creating IAM role for Lambda..."
awslocal iam create-role \
    --role-name lambda-execution-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

# Attach full access policies to the IAM role
echo "Attaching policies to the IAM role..."
awslocal iam put-role-policy \
    --role-name lambda-execution-role \
    --policy-name lambda-full-access \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": ["s3:*", "dynamodb:*"],
            "Resource": "*"
        }]
    }'

# Package and deploy Lambda function
echo "Packaging Lambda function..."
zip lambda_function.zip lambda_function.py

echo "Deploying Lambda function..."
awslocal lambda create-function \
    --function-name csv-processor \
    --runtime python3.10 \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://lambda_function.zip \
    --role arn:aws:iam::000000000000:role/lambda-execution-role \
    --layers arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python310:23 \
    --memory-size 1024 \
    --timeout 30

# Add S3 invoke permission to Lambda
echo "Adding S3 invoke permission to Lambda..."
awslocal lambda add-permission \
    --function-name csv-processor \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --statement-id s3-invoke \
    --source-arn arn:aws:s3:::csv-bucket

# Set up S3 event trigger
echo "Setting up S3 event trigger..."
awslocal s3api put-bucket-notification-configuration \
    --bucket csv-bucket \
    --notification-configuration '{
        "LambdaFunctionConfigurations": [{
            "Id": "csv-upload-trigger",
            "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:csv-processor",
            "Events": ["s3:ObjectCreated:*"]
        }]
    }'

echo "Setup complete!"