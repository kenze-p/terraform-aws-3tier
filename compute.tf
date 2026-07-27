# ─── EC2 Instances ───────────────────────────────────────────────────────────
resource "aws_instance" "web" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.backend[count.index].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3.name

  user_data = <<-USERDATA
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
  USERDATA

  tags = {
    Name = "${var.project_name}-ec2-${count.index + 1}"
  }
}
