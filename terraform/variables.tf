variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "streetcode"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type eligible for AWS Free Tier."
  type        = string
  default     = "t3.micro"
}

variable "public_key_path" {
  description = "Path to SSH public key for EC2 authentication."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH into the instance."
  type        = string
  default     = "0.0.0.0/0"
}

variable "ebs_volume_size" {
  description = "Size of the root EBS volume in GB."
  type        = number
  default     = 30
}