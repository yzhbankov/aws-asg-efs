output "aws_region" {
  value = var.AWS_REGION
}

# Output the DNS of the EFS file system
output "efs_dns" {
  value = aws_efs_file_system.efs.dns_name
}

# Output the ID of the launch template
output "launch_template_id" {
  value = aws_launch_template.launch_template.id
}
