# AWS 3-Tier Infrastructure with Terraform

A 3-tier AWS infrastructure — networking, compute, and storage — provisioned with Terraform and configured with Ansible, built as a hands-on DevOps technical assessment.

## Architecture

```
                              Internet
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  Application Load Balancer│
                    │   (public, port 80)       │
                    └────────────┬─────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
     ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
     │  Frontend Subnet │ │  Frontend Subnet │ │  Frontend Subnet │
     │   AZ-a (public)  │ │   AZ-b (public)  │ │   AZ-c (public)  │
     └─────────────────┘ └─────────────────┘ └─────────────────┘
              │                  │                  │
              ▼                  ▼                  ▼
     ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
     │  Backend Subnet  │ │  Backend Subnet  │ │  Backend Subnet  │
     │  EC2 (nginx)      │ │  EC2 (nginx)      │ │  EC2 (nginx)      │
     │  AZ-a (private)   │ │  AZ-b (private)   │ │  AZ-c (private)   │
     └─────────────────┘ └─────────────────┘ └─────────────────┘
              │
              ▼ (outbound only, via NAT Gateway)
     ┌─────────────────────────────────────────┐
     │        DB Subnets (isolated, 3 AZs)       │
     │   reserved for future database tier —    │
     │   no internet route, no DB resource yet  │
     └─────────────────────────────────────────┘

     S3 bucket (private, static content) ◄── synced to each EC2 via IAM role
```

## What Terraform Provisions

- **VPC** with 9 subnets across 3 Availability Zones:
  - 3 frontend subnets (public) → routed to Internet Gateway, host the ALB
  - 3 backend subnets (private) → routed to a NAT Gateway for outbound-only access, host the EC2 instances
  - 3 database subnets (isolated) → no route out (blackhole route table); reserved for a future database tier, no DB resource currently deployed
- **3 EC2 instances** (Ubuntu 22.04 LTS, t3.micro), one per AZ, placed in the private backend subnets — not directly internet-facing
- **Application Load Balancer** (internet-facing, port 80) distributing traffic to the EC2 instances via a target group with health checks
- **S3 bucket** (public access blocked) for static content, synced to each instance
- **IAM role + instance profile** granting the EC2 instances read-only access to the S3 bucket
- **Security groups**: the ALB accepts HTTP/HTTPS from the internet; the EC2 instances accept HTTP only from the ALB's security group (not from the internet directly)

Terraform is organized into logical files: [`network.tf`](network.tf), [`security.tf`](security.tf), [`storage.tf`](storage.tf), [`compute.tf`](compute.tf), [`loadbalancer.tf`](loadbalancer.tf), [`providers.tf`](providers.tf), [`variables.tf`](variables.tf).

## Configuration Management

Two complementary layers handle the web server setup:

- **Terraform `user_data`** bootstraps each instance on first boot: installs nginx and the AWS CLI, writes a placeholder page, and does an initial sync from the S3 bucket.
- **Ansible** ([`ansible/playbook.yml`](ansible/playbook.yml)) handles repeatable, idempotent configuration after provisioning — install nginx/AWS CLI, deploy an nginx config from a Jinja2 template ([`templates/nginx.conf.j2`](ansible/templates/nginx.conf.j2)), re-sync content from S3, and reload nginx via a handler. This is the layer used to make configuration changes without having to replace or restart instances.

## Tech Stack

- Terraform ~> 5.0
- AWS (VPC, EC2, ALB, S3, IAM, NAT Gateway)
- Ansible (nginx installation and configuration via template)
- Ubuntu 22.04 LTS

## Quick Start

```bash
# Clone the repo
git clone https://github.com/kenze-p/terraform-aws-3tier.git
cd terraform-aws-3tier

# Configure AWS credentials
aws configure

# Deploy infrastructure
terraform init
terraform plan
terraform apply

# Configure the instances with Ansible
export S3_BUCKET=$(terraform output -raw s3_bucket_name)
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml

# Destroy when done
terraform destroy
```

## Configuration

Key variables (see [`variables.tf`](variables.tf), override in a `terraform.tfvars` — not committed):

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `eu-central-1` | AWS region |
| `instance_type` | `t3.micro` | EC2 instance type |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |

## Security Notes

- EC2 instances sit in private subnets and are only reachable through the ALB — not directly exposed to the internet.
- The S3 bucket blocks all public access; access is granted only to the EC2 instances via an IAM role.
- AWS credentials are never stored in the repo — `.gitignore` excludes `.tfstate`, `.tfvars`, and `.aws/`.
- Database subnets are isolated with no outbound route, ready for a future RDS or similar resource without requiring network changes.

## Deployment Notes

This project uses manual deployment (`terraform apply` + `ansible-playbook`, run locally) rather than a CI/CD pipeline — unlike the companion [gs-rest-service](https://github.com/kenze-p/gs-rest-service) project, which is fully automated via GitHub Actions.

## Screenshots

See the [`screenshots/`](screenshots/) folder for captures of the running VPC, EC2 instances, and Application Load Balancer (healthy target group) taken while the infrastructure was live.

> Note: confirm this folder actually contains images before sharing the repo — if it's empty, either add the captures or remove this section.

## Project Status

Built as a hands-on technical assessment to demonstrate 3-tier network design and infrastructure-as-code practices. The AWS infrastructure has since been decommissioned to avoid ongoing costs; the screenshots above were captured while it was running. The Terraform and Ansible code remain fully intact and reproducible.
