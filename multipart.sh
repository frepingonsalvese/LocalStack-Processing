#!/bin/bash

# Step 1: Initiate multipart upload
echo "Initiating multipart upload..."
upload_id=$(awslocal s3api create-multipart-upload --bucket csv-bucket --key people-100000.csv --query 'UploadId' --output text)
echo "Upload ID: $upload_id"

# Step 2: Split the file into 3MB parts
echo "Splitting the file..."
split -b 5M people-100000.csv people-100000-part-

# Step 3: Upload each part
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

# Step 4: List parts to get ETags
echo "Listing parts..."
parts=$(awslocal s3api list-parts --bucket csv-bucket --key people-100000.csv --upload-id $upload_id --query 'Parts[*].{PartNumber: PartNumber, ETag: ETag}' --output json)
echo "Parts: $parts"

# Step 5: Complete multipart upload
echo "Completing multipart upload..."
awslocal s3api complete-multipart-upload \
  --bucket csv-bucket \
  --key people-100000.csv \
  --upload-id $upload_id \
  --multipart-upload "{\"Parts\": $parts}"

echo "Multipart upload completed successfully!"