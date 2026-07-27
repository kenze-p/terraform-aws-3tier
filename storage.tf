# ─── Random suffix za S3 bucket ime ─────────────────────────────────────────
resource "random_id" "suffix" {
  byte_length = 4
}

# ─── S3 Bucket ───────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "static" {
  bucket        = "${var.project_name}-static-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "${var.project_name}-static" }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── IAM Role za EC2 → S3 pristup ────────────────────────────────────────────
resource "aws_iam_role" "ec2_s3" {
  name = "${var.project_name}-ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-ec2-s3-role" }
}

resource "aws_iam_role_policy" "ec2_s3" {
  name = "${var.project_name}-ec2-s3-policy"
  role = aws_iam_role.ec2_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.static.arn,
        "${aws_s3_bucket.static.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_s3" {
  name = "${var.project_name}-ec2-s3-profile"
  role = aws_iam_role.ec2_s3.name
}
