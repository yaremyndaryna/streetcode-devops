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

resource "aws_instance" "k3s_node" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  key_name             = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  root_block_device {
    volume_size           = var.ebs_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              apt-get update -y
              apt-get install -y curl git docker.io

              curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

              mkdir -p /home/ubuntu/.kube
              cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
              chown -R ubuntu:ubuntu /home/ubuntu/.kube

              echo "alias k='kubectl'" >> /home/ubuntu/.bashrc
              echo "source <(kubectl completion bash)" >> /home/ubuntu/.bashrc
              EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-k3s-node"
  }
}

resource "aws_eip" "k3s_eip" {
  instance = aws_instance.k3s_node.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip"
  }
}