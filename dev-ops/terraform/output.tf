output "aws_region" {
  value = var.AWS_REGION
}

output "efs_dns" {
  value = aws_efs_file_system.efs.dns_name
}

output "launch_template_id" {
  value = aws_launch_template.launch_template.id
}

output "cloud_front_domain_name" {
  value = aws_cloudfront_distribution.cloudfront_distribution.domain_name
}

output "ald_dns" {
  value = aws_lb.alb.dns_name
}
