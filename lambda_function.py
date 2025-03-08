import json
import boto3
import pandas as pd
from datetime import datetime
from io import StringIO

# Initialize clients
s3 = boto3.client('s3', endpoint_url='http://host.docker.internal:4566')
dynamodb = boto3.resource('dynamodb', endpoint_url='http://host.docker.internal:4566')
table = dynamodb.Table('csv-metadata')

def lambda_handler(event, context):
    try:
        # Extract bucket and object key from the S3 event
        bucket_name = event['Records'][0]['s3']['bucket']['name']
        object_key = event['Records'][0]['s3']['object']['key']

        # Download the CSV file
        response = s3.get_object(Bucket=bucket_name, Key=object_key)
        csv_data = response['Body'].read().decode('utf-8')

        # Process the CSV file
        df = pd.read_csv(StringIO(csv_data))

        # Extract metadata
        metadata = {
            'filename': object_key,
            'upload_timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'file_size_bytes': response['ContentLength'],
            'row_count': len(df),
            'column_count': len(df.columns),
            'column_names': df.columns.tolist()
        }

        # Store metadata in DynamoDB
        table.put_item(Item=metadata)

        return {
            'statusCode': 200,
            'body': json.dumps('Metadata extracted and stored successfully!')
        }

    except Exception as e:
        print("Error:", str(e))
        return {
            'statusCode': 500,
            'body': json.dumps('Error processing the file')
        }