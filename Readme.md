# File Processing System Using Local Stack -  localized AWS environment

This document provides a breakdown of each command used in the setup script for configuring S3, DynamoDB, IAM, and Lambda in LocalStack.

I utilized Localstack on the **DOCKER DESKTOP EXTENSION** for this Project.

## 1. Create S3 Bucket

```bash
echo "Creating S3 bucket..."
awslocal s3 mb s3://csv-bucket

```

- `awslocal s3 mb s3://csv-bucket` creates a new S3 bucket named `csv-bucket`.
  
![Screenshot from 2025-03-08 12-55-22](https://github.com/user-attachments/assets/73790305-26f2-42a6-8249-4281cda5a2dd)


## 2. Create DynamoDB Table

```bash
echo "Creating DynamoDB table..."
awslocal dynamodb create-table \
    --table-name csv-metadata \
    --attribute-definitions AttributeName=filename,AttributeType=S \
    --key-schema AttributeName=filename,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST

```

- Defines a DynamoDB table named `csv-metadata`.
- Uses `filename` as the primary key (hash key).
- Sets billing mode to `PAY_PER_REQUEST` (no need to specify read/write capacity units).

![Screenshot from 2025-03-08 12-55-38](https://github.com/user-attachments/assets/dfde51fc-e563-44dc-b1ed-042909afe7a5)


## 3. Create IAM Role for Lambda

```bash
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

```

- Creates an IAM role named `lambda-execution-role`.
- Grants Lambda permission to assume this role.

![Screenshot from 2025-03-08 12-55-57](https://github.com/user-attachments/assets/7da42e93-a88b-4258-853f-9a8d2b023e33)


## 4. Attach IAM Policies to Lambda Role

```bash
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

```
- Grants full access to S3 and DynamoDB for the `lambda-execution-role`.

![Screenshot from 2025-03-08 12-56-42](https://github.com/user-attachments/assets/a25ed258-fd78-43c2-883e-df5dd4e641a6)


## 5. Package and Deploy Lambda Function

```bash
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

```

- Zips the `lambda_function.py` file.
- Deploys the Lambda function named `csv-processor`.
- Uses `python3.10` runtime.
- Sets the memory size to `1024 MB`.
- Sets a timeout of `30 seconds`.
- Includes a Pandas AWS SDK Lambda Layer. - **arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python310:23**

![Screenshot from 2025-03-08 12-56-59](https://github.com/user-attachments/assets/d074e2e2-fab7-4333-88cc-9d55bfcdb8e5)


## 6. Add S3 Event Trigger to Lambda

```bash
echo "Adding S3 invoke permission to Lambda..."
awslocal lambda add-permission \
    --function-name csv-processor \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --statement-id s3-invoke \
    --source-arn arn:aws:s3:::csv-bucket

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

```

- Grants S3 permission to invoke the Lambda function.
- Sets up an event trigger so that whenever a file is uploaded to `csv-bucket`, the `csv-processor` Lambda function is triggered.

![Screenshot from 2025-03-08 12-56-59](https://github.com/user-attachments/assets/3835c9d5-80df-4efc-978a-27587cc4936c)


## 7. Multipart Upload Script Breakdown

### ***Why Use Multipart Upload?***

Since the file size was **12MB**, uploading it in a single request could be inefficient and prone to failure if interrupted. Multipart upload improves performance and reliability by splitting the file into smaller **5MB chunks** and uploading them separately. This approach ensures:

- **Efficient large file handling**: Instead of a single large transfer, multiple smaller parts are uploaded in parallel.
- **Resilience to failures**: If any part fails, only that part needs to be reuploaded rather than the entire file.
- **Faster upload speeds**: Multiple parts can be uploaded concurrently, reducing total upload time.

This is why we initiated a multipart upload before sending the file to S3

### Part 1: Initiate Multipart Upload

```bash
echo "Initiating multipart upload..."
upload_id=$(awslocal s3api create-multipart-upload --bucket csv-bucket --key people-100000.csv --query 'UploadId' --output text)
echo "Upload ID: $upload_id"

```

- Initiates a multipart upload session for `people-100000.csv` and stores the upload ID.
  
![Screenshot from 2025-03-08 13-23-35](https://github.com/user-attachments/assets/dd6ca4ac-9897-49cd-853e-a451adb7d530)


### Part 2: Split File into Parts

```bash
echo "Splitting the file..."
split -b 5M people-100000.csv people-100000-part-

```

- Splits `people-100000.csv` into 5MB chunks with the prefix `people-100000-part-`.

![Screenshot from 2025-03-08 13-24-33](https://github.com/user-attachments/assets/8fc7ab16-56fb-43a2-88e9-ca3510070733)


### Part 3: Upload Each Part

```bash
echo "Uploading parts..."
part_number=1
for file in people-100000-part-*; do
  echo "Uploading part $part_number: $file"
  awslocal s3api upload-part \
    --bucket csv-bucket \
    --key people-100000.csv \
    --part-number $part_number \
    --body $file \
    --upload-id $upload_id
  part_number=$((part_number + 1))
done

```

- Iterates through the split files and uploads each part using the stored upload ID.
- Increments the `part_number` for each chunk uploaded.

![Screenshot from 2025-03-08 13-25-04](https://github.com/user-attachments/assets/d124d244-4487-4b53-bed8-f2fae37317f2)


### Part 4: Complete Multipart Upload

```bash
echo "Completing multipart upload..."
parts=$(awslocal s3api list-parts --bucket csv-bucket --key people-100000.csv --upload-id $upload_id --query 'Parts[*].{PartNumber: PartNumber, ETag: ETag}' --output json)
awslocal s3api complete-multipart-upload \
  --bucket csv-bucket \
  --key people-100000.csv \
  --upload-id $upload_id \
  --multipart-upload "{\"Parts\": $parts}"

echo "Multipart upload completed successfully!"

```

- Lists all uploaded parts and retrieves their PartNumbers and ETags.
- Completes the multipart upload by passing the upload ID and the list of parts to S3.

![Screenshot from 2025-03-08 13-25-38](https://github.com/user-attachments/assets/f4d974bd-c981-41e3-96b4-7b3489546eb0)


## **Sample File Description**

The project uses a CSV file named **"people-100000.csv"**, which contains **100,000 rows** of structured data related to individuals. The file size is **approximately 11.6MB (11,600,795 bytes)** and consists of **9 columns**.

### **Column Information:**

The dataset primarily includes personal details such as:

- **User Id** – A unique identifier assigned to each user.
- **First Name & Last Name** – The user's full name.
- **Sex** – Gender of the user.
- **Email & Phone** – Contact details of the user.
- **Date of Birth** – User’s birth date.
- **Job Title** – The professional title associated with the user.

This structured dataset was chosen to simulate a real-world scenario where user metadata is stored and processed efficiently in **AWS S3** and **DynamoDB**.

![Screenshot from 2025-03-08 13-11-36](https://github.com/user-attachments/assets/d7c87edc-cc41-4b22-82ee-0a3464193a60)


## File Upload and Lambda Processing

- Once the file is successfully uploaded to S3, the S3 event trigger invokes the `csv-processor` Lambda function.
  
![Screenshot from 2025-03-08 13-29-01](https://github.com/user-attachments/assets/ce687a7d-e4c2-4324-a3cd-5c3eb8ff44d0)


- The Lambda function extracts metadata from the uploaded file and stores it in the DynamoDB table `csv-metadata`.

![Screenshot from 2025-03-08 13-29-13](https://github.com/user-attachments/assets/24e56869-bf07-4696-98b3-17afe4252b58)


## **METADATA STORED IN DYNAMO DB**

![Screenshot from 2025-03-08 12-53-34](https://github.com/user-attachments/assets/d7b2972c-e61c-464d-88fa-2e21b01a08ef)


![Screenshot from 2025-03-08 12-53-42](https://github.com/user-attachments/assets/43d06b19-e5a7-463a-b803-6f4ac0e55465)


## Conclusion

This setup ensures:

- An S3 bucket is created for storing CSV files.
- A DynamoDB table is available to store metadata.
- A Lambda function processes CSV uploads.
- S3 events trigger the Lambda function.
- IAM permissions allow Lambda to access required resources.
- Multipart upload is used for large files.

[]()

