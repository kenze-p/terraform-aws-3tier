terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── VPC ────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-vpc" }
}

# ─── Internet Gateway ────────────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ─── Frontend Subnets (public) ───────────────────────────────────────────────
resource "aws_subnet" "frontend" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.frontend_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-frontend-${count.index + 1}" }
}

# ─── Backend Subnets (private) ───────────────────────────────────────────────
resource "aws_subnet" "backend" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.backend_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "${var.project_name}-backend-${count.index + 1}" }
}

# ─── Database Subnets (isolated) ─────────────────────────────────────────────
resource "aws_subnet" "db" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "${var.project_name}-db-${count.index + 1}" }
}

# ─── NAT Gateway ─────────────────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.frontend[0].id
  tags          = { Name = "${var.project_name}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

# ─── Route Table: Frontend → IGW ─────────────────────────────────────────────
resource "aws_route_table" "frontend" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.project_name}-rt-frontend" }
}

resource "aws_route_table_association" "frontend" {
  count          = 3
  subnet_id      = aws_subnet.frontend[count.index].id
  route_table_id = aws_route_table.frontend.id
}

# ─── Route Table: Backend → NAT ──────────────────────────────────────────────
resource "aws_route_table" "backend" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.project_name}-rt-backend" }
}

resource "aws_route_table_association" "backend" {
  count          = 3
  subnet_id      = aws_subnet.backend[count.index].id
  route_table_id = aws_route_table.backend.id
}

# ─── Route Table: DB → Blackhole (nema rute) ─────────────────────────────────
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-rt-db" }
}

resource "aws_route_table_association" "db" {
  count          = 3
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# ─── Security Group: ALB ─────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "Allow HTTP and HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-alb" }
}

# ─── Security Group: EC2 ─────────────────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-sg-ec2"
  description = "Allow HTTP only from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-ec2" }
}

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

# ─── EC2 Instances ───────────────────────────────────────────────────────────
resource "aws_instance" "web" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.backend[count.index].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3.name

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx python3-pip unzip curl
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    systemctl enable nginx
    systemctl start nginx
    echo "<h1>DevOps Assessment - Server ${count.index + 1}</h1>" > /var/www/html/index.html
    /usr/local/bin/aws s3 sync s3://${aws_s3_bucket.static.bucket}/html /var/www/html --region ${var.aws_region} || true
  EOF

  tags = {
    Name = "${var.project_name}-ec2-${count.index + 1}"
  }
}

# ─── Application Load Balancer ───────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.frontend[*].id

  tags = { Name = "${var.project_name}-alb" }
}

# ─── Target Group ────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "${var.project_name}-tg" }
}

# ─── Target Group Attachments ─────────────────────────────────────────────────
resource "aws_lb_target_group_attachment" "web" {
  count            = 3
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# ─── HTTP Listener ────────────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ─── Current account identity ─────────────────────────────────────────────────
data "aws_caller_identity" "current" {}