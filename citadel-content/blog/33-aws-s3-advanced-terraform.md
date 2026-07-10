# AWS S3 Advanced: Replication, Encryption, and Access Control with Terraform

**Pillar:** AWS Infrastructure
**SEO Target:** aws s3 terraform replication encryption object lock access control production
**Word Count:** ~1600

S3 is the backbone of most AWS architectures. This guide covers advanced S3 patterns: cross-region replication, object lock for immutability, S3 Object Lambda for on-the-fly transformation, and airtight access controls — all with Terraform.

## Primary Bucket with Full Security Controls

```hcl
resource "aws_s3_bucket" "primary" {
  bucket        = "${var.prefix}-primary-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "prod"
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object_lock_configuration" "primary" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.primary.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.retention_days
    }
  }
}
```

## Cross-Region Replication

```hcl
resource "aws_s3_bucket" "replica" {
  provider      = aws.dr_region
  bucket        = "${var.prefix}-replica-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "prod"
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.dr_region
  bucket   = aws_s3_bucket.replica.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_iam_role" "replication" {
  name = "${var.prefix}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "replication-policy"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = "${aws_s3_bucket.replica.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "primary" {
  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "full-replication"
    status = "Enabled"

    filter {}

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD_IA"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.s3_replica.arn
      }

      replication_time {
        status = "Enabled"
        time   { minutes = 15 }
      }

      metrics {
        status = "Enabled"
        event_threshold { minutes = 15 }
      }
    }

    delete_marker_replication {
      status = "Enabled"
    }
  }
}
```

## Intelligent Tiering + Lifecycle

```hcl
resource "aws_s3_bucket_intelligent_tiering_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id
  name   = "EntireBucket"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "delete-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }

  rule {
    id     = "noncurrent-version-expiry"
    status = "Enabled"

    noncurrent_version_expiration { noncurrent_days = 90 }
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
  }
}
```

## Bucket Policy

```hcl
data "aws_iam_policy_document" "primary" {
  statement {
    sid    = "DenyNonTLS"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.primary.arn, "${aws_s3_bucket.primary.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyNonKMSEncryption"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.primary.arn}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid    = "AllowAppAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.app_role_arn]
    }
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.primary.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "primary" {
  bucket = aws_s3_bucket.primary.id
  policy = data.aws_iam_policy_document.primary.json
}
```

## S3 Object Lambda

```hcl
resource "aws_s3_access_point" "primary" {
  bucket = aws_s3_bucket.primary.id
  name   = "${var.prefix}-access-point"
}

resource "aws_s3control_object_lambda_access_point" "transform" {
  account_id = data.aws_caller_identity.current.account_id
  name       = "${var.prefix}-transform"

  configuration {
    supporting_access_point = aws_s3_access_point.primary.arn

    transformation_configuration {
      actions = ["GetObject"]
      content_transformation {
        aws_lambda {
          function_arn = aws_lambda_function.s3_transformer.arn
        }
      }
    }
  }
}
```

## Production Checklist

- [ ] Versioning enabled on primary and replica buckets
- [ ] KMS encryption with bucket key enabled (reduces API calls 99%)
- [ ] Block public access on all four settings
- [ ] Bucket policy: deny non-TLS and non-KMS encryption at upload
- [ ] Cross-region replication with 15-minute SLA (S3 RTC)
- [ ] Object Lock in GOVERNANCE mode for compliance workloads
- [ ] Intelligent Tiering auto-moves cold objects to archive storage
- [ ] Lifecycle: abort incomplete multiparts after 7d, expire old versions after 90d
- [ ] S3 Access Logging to separate audit bucket

Advanced S3 with replication and object lock gives you an RPO of 15 minutes and immutable audit trails — two requirements that tend to show up together in regulated industries.
