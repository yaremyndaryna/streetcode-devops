# AMI для Ubuntu 22.04 x86_64 (Intel/AMD)
data "aws_ami" "ubuntu_x86" {
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

# 1. App Node (K3s + App Services)
resource "aws_instance" "k3s_node" {
  ami                    = data.aws_ami.ubuntu_x86.id
  instance_type          = var.app_instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  root_block_device {
    volume_size           = var.ebs_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-node"
    Role = "app"
  }
}

# Elastic IP для App Node
resource "aws_eip" "k3s_eip" {
  instance = aws_instance.k3s_node.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-app-eip"
  }
}

# 2. Tools Node (Jenkins + Prometheus + Grafana via Docker Compose)
resource "aws_instance" "tools_node" {
  ami                    = data.aws_ami.ubuntu_x86.id # Виправлено: використовуємо x86 AMI під t3.small
  instance_type          = var.tools_instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  root_block_device {
    volume_size           = var.ebs_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tools-node"
    Role = "tools"
  }
}

# Elastic IP для Tools Node
resource "aws_eip" "tools_eip" {
  instance = aws_instance.tools_node.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-tools-eip"
  }
}