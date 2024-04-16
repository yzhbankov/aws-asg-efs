# Create a new EFS file system with multi-AZ support
resource "aws_efs_file_system" "efs" {
  creation_token   = "${terraform.workspace}-yz-efs" # A unique name for your EFS file system
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  lifecycle_policy {
    # Configure automatic backups (optional)
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "alpha" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.private_subnet_a.id
}

resource "aws_efs_mount_target" "beta" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.private_subnet_b.id
}

resource "aws_efs_mount_target" "gamma" {
  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.private_subnet_c.id
}

# Create an Application Load Balancer (ALB)
resource "aws_lb" "alb" {
  name               = "${terraform.workspace}-yz-alb"
  internal           = false # Set to true if internal ALB
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  security_groups    = [aws_security_group.web_server_sg.id] # Attach your web server security group
}

# Create a target group for the ALB
resource "aws_lb_target_group" "target_group" {
  name     = "${terraform.workspace}-yz-tg"
  port     = 80     # Port where your instances are listening
  protocol = "HTTP" # Protocol used by your instances
  vpc_id   = aws_vpc.web_server_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "sh_front_end" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

# Create a launch template
resource "aws_launch_template" "launch_template" {
  name_prefix            = "${terraform.workspace}-yz-asg-launch-template"
  image_id               = "ami-051f8a213df8bc089" # Amazon Linux 2 AMI ID
  instance_type          = "t2.micro"              # Example instance type, replace with your desired type
  vpc_security_group_ids = [aws_security_group.efs_sg.id, aws_security_group.web_server_sg.id]

  # Define user data for the instance
  user_data = base64encode(<<EOF
#!/bin/bash
# Install NFS utilities
yum -y install nginx

# Add configuration for /directory location
sudo sh -c 'cat <<EOF > /etc/nginx/default.d/directory.conf
location /directory {
    alias /mnt/efs;
    autoindex on;
}
EOF'

# Test NGINX configuration
sudo nginx -t

# Start NGINX
sudo systemctl start nginx

# Enable NGINX to start on boot
sudo systemctl enable nginx

# Install NFS utilities
yum -y install nfs-utils

# Create a directory to mount the EFS
mkdir /mnt/efs

# Mount the EFS filesystem
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.efs.dns_name}:/ /mnt/efs

# Add the EFS mount to /etc/fstab to mount on every reboot
echo "${aws_efs_file_system.efs.dns_name}:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab
EOF
  )
}

# Create an Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  name                = "${terraform.workspace}-yz-asg"
  min_size            = 1
  desired_capacity    = 1
  max_size            = 3
  vpc_zone_identifier = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id, aws_subnet.private_subnet_c.id] # Add your subnet IDs here

  # Connect to the target group
  target_group_arns = [aws_lb_target_group.target_group.arn]

  # Use the launch template created above
  launch_template {
    id      = aws_launch_template.launch_template.id
    version = "$Latest"
  }
}

# Create a scaling policy based on CPU utilization
resource "aws_autoscaling_policy" "cpu_scaling_policy" {
  name                   = "scale-on-cpu"
  policy_type            = "TargetTrackingScaling" # Use target tracking scaling policy
  autoscaling_group_name = aws_autoscaling_group.asg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }
}

# Create a CloudFront distribution
resource "aws_cloudfront_distribution" "cloud_front_distribution" {
  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "${terraform.workspace}-yz-alb-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "${terraform.workspace}-yz-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
