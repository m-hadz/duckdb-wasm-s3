#!/bin/sh
set -eu

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "local/$S3_BUCKET"

cat > /tmp/policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": ["*"] },
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::$S3_BUCKET/*"]
    },
    {
      "Effect": "Allow",
      "Principal": { "AWS": ["*"] },
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::$S3_BUCKET"]
    }
  ]
}
JSON
mc anonymous set-json /tmp/policy.json "local/$S3_BUCKET"

mc mirror --overwrite --exclude ".gitkeep" /seed "local/$S3_BUCKET"
