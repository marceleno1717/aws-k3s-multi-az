# resource "aws_instance" "test-instance" {
#   subnet_id              = aws_subnet.eu-west-3a-public.id
#   ami                    = var.ami
#   instance_type          = "t3.micro"
#   key_name               = var.key_pair_name
#   vpc_security_group_ids = [aws_security_group.manager-sg.id]
# }

data "aws_region" "current" {}

data "aws_ec2_managed_prefix_list" "ec2_instance_connect" {
  name = "com.amazonaws.${data.aws_region.current.region}.ec2-instance-connect"
}

resource "aws_security_group" "managers-sg" {
  name   = "managers-sg"
  vpc_id = aws_vpc.k3s.id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["10.0.0.0/16"]
    protocol    = "-1"
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = ["${chomp(data.http.public_ip.response_body)}/32"]
    protocol    = "tcp"
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    cidr_blocks = ["${aws_eip.nat.public_ip}/32"]
    protocol    = "tcp"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["${chomp(data.http.public_ip.response_body)}/32"]
    protocol    = "tcp"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.ec2_instance_connect.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
  }
}

resource "random_password" "k3s-node-token" {
  length  = 48
  special = false
}

resource "aws_instance" "manager-1" {
  subnet_id              = aws_subnet.k3s-public["A"].id
  ami                    = var.ami
  instance_type          = var.manager_instance_type
  vpc_security_group_ids = [aws_security_group.managers-sg.id]
  key_name               = "k3s"

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y

              # 1. Create directory and pre-seed manager config
              mkdir -p /etc/rancher/k3s
              cat <<'CONFIG' > /etc/rancher/k3s/config.yaml
              cluster-init: true
              tls-san:
                - "${aws_lb.k3s-nlb.dns_name}"
              token: "${random_password.k3s-node-token.result}"
              write-kubeconfig-mode: "0644"
              CONFIG

              # 2. Run the K3s server installer
              curl -sfL https://get.k3s.io | sh -s - server
              EOF

  tags = {
    Name = "Manager Node 1"
    AZ   = aws_subnet.k3s-public["A"].availability_zone
  }
}

resource "aws_instance" "manager-peers" {
  for_each = {
    "AZ-B" = aws_subnet.k3s-public["B"],
    "AZ-C" = aws_subnet.k3s-public["C"],
  }

  subnet_id              = each.value.id
  ami                    = var.ami
  instance_type          = var.manager_instance_type
  vpc_security_group_ids = [aws_security_group.managers-sg.id]
  key_name               = "k3s"

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y

              # 1. Create directory and pre-seed manager peer config
              mkdir -p /etc/rancher/k3s
              cat <<'CONFIG' > /etc/rancher/k3s/config.yaml
              server: "https://${aws_instance.manager-1.private_ip}:6443"
              tls-san:
                - "${aws_lb.k3s-nlb.dns_name}"
              token: "${random_password.k3s-node-token.result}"
              write-kubeconfig-mode: "0644"
              CONFIG

              # 2. Run the K3s server installer
              curl -sfL https://get.k3s.io | sh -s - server
              EOF

  tags = {
    Name = "Manager Peer"
    AZ   = each.value.availability_zone
  }
}

resource "aws_security_group" "workers-sg" {
  name   = "workers-sg"
  vpc_id = aws_vpc.k3s.id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["10.0.0.0/16"]
    protocol    = "-1"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "TCP"
    security_groups = [aws_security_group.eice_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
  }
}


resource "aws_instance" "workers" {
  for_each = aws_subnet.k3s-private

  subnet_id              = each.value.id
  ami                    = var.ami
  instance_type          = var.worker_instance_type
  vpc_security_group_ids = [aws_security_group.workers-sg.id]

  user_data = <<-EOF
                #!/bin/bash
                apt-get update -y

                # 1. Create directory and pre-seed worker config
                mkdir -p /etc/rancher/k3s
                cat <<'CONFIG' > /etc/rancher/k3s/config.yaml
                server: "https://${aws_lb.k3s-nlb.dns_name}:6443"
                token: "${random_password.k3s-node-token.result}"
                CONFIG

                # 2. Run the K3s agent installer
                curl -sfL https://get.k3s.io | sh -s - agent
              EOF

  tags = {
    Name = "Worker Node"
    AZ   = each.value.availability_zone
  }
}

resource "aws_security_group" "eice_sg" {
  name        = "eice_sg"
  description = "Security group for EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.k3s.id

  lifecycle {
    create_before_destroy = true
  }

  # Allow the endpoint to send SSH outbound to private instances
  egress {
    description = "Allow SSH to internal VPC instances"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "aws_ec2_instance_connect_endpoint" "private_eice" { # ec2 isntance conenct endpoint
  subnet_id          = aws_subnet.k3s-private["A"].id         # Any private subnet
  security_group_ids = [aws_security_group.eice_sg.id]

  tags = {
    Name = "k3s-private-eice"
  }
}

output "managers_public_ips" {
  description = "Public IPs of all manager nodes"
  value = concat(
    [aws_instance.manager-1.public_ip],
    [for mp in aws_instance.manager-peers : mp.public_ip]
  )
}

# output "managers_private_ips" {
#   description = "Private IPs of all manager nodes"
#   value = concat(
#     [aws_instance.manager-1.private_ip],
#     [for mp in aws_instance.manager-peers : mp.private_ip]
#   )
# }
