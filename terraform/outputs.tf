output "app_node_public_ip" {
  description = "Elastic Public IP address of the App node"
  value       = aws_eip.k3s_eip.public_ip
}

output "app_node_private_ip" {
  description = "Private IP of the App node (for internal communication)"
  value       = aws_instance.k3s_node.private_ip
}

output "tools_node_public_ip" {
  description = "Elastic Public IP address of the Tools node"
  value       = aws_eip.tools_eip.public_ip
}

output "tools_node_private_ip" {
  description = "Private IP of the Tools node"
  value       = aws_instance.tools_node.private_ip
}

output "ssh_connect_app" {
  description = "Command to SSH into App Node"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_eip.k3s_eip.public_ip}"
}

output "ssh_connect_tools" {
  description = "Command to SSH into Tools Node"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_eip.tools_eip.public_ip}"
}