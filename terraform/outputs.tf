output "public_ip" {
  description = "Elastic Public IP address of the k3s node"
  value       = aws_eip.k3s_eip.public_ip
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.k3s_node.id
}

output "ssh_connect_command" {
  description = "Command to connect via SSH"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_eip.k3s_eip.public_ip}"
}

output "kubeconfig_fetch_command" {
  description = "Command to fetch kubeconfig file to your local machine"
  value       = "scp ubuntu@${aws_eip.k3s_eip.public_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/config-streetcode"
}