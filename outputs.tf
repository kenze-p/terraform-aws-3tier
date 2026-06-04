output "alb_dns_name" {
  description = "ALB public DNS name - otvori ovo u browseru"
  value       = aws_lb.main.dns_name
}

output "ec2_instance_ids" {
  description = "EC2 instance IDs"
  value       = aws_instance.web[*].id
}

output "ec2_private_ips" {
  description = "EC2 private IP adrese"
  value       = aws_instance.web[*].private_ip
}

output "s3_bucket_name" {
  description = "S3 bucket ime"
  value       = aws_s3_bucket.static.bucket
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}