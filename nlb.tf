# Load Balancers

resource "aws_security_group" "nlb-sg" {
  name   = "nlb-sg"
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
    cidr_blocks = [for addr in aws_nat_gateway.k3s-nat.regional_nat_gateway_address : "${addr.public_ip}/32"]
    protocol    = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
  }
}

resource "aws_lb" "k3s-nlb" {
  subnets = [for subnet in aws_subnet.k3s-public : subnet.id]

  # subnet_mapping {
  #   subnet_id = aws_subnet.eu-west-3a-public.id
  # }

  # subnet_mapping {
  #   subnet_id = aws_subnet.eu-west-3b-public.id
  # }

  # subnet_mapping {
  #   subnet_id = aws_subnet.eu-west-3c-public.id
  # }

  internal                         = false
  load_balancer_type               = "network"
  security_groups                  = [aws_security_group.nlb-sg.id]
  enable_cross_zone_load_balancing = true
}

output "nlb-dns" {
  value = aws_lb.k3s-nlb.dns_name
}

resource "aws_lb_target_group" "nlb-target-group" {
  vpc_id             = aws_vpc.k3s.id
  port               = 6443
  protocol           = "TCP"
  target_type        = "instance"
  preserve_client_ip = false

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "nlb-listener" {
  load_balancer_arn = aws_lb.k3s-nlb.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb-target-group.arn
  }
}

resource "aws_lb_target_group_attachment" "nlb-target-attachment" {
  for_each = {
    "manager-1" = aws_instance.manager-1.id,
    "manager-B" = aws_instance.manager-peers["AZ-B"].id,
    "manager-C" = aws_instance.manager-peers["AZ-C"].id
  }

  target_group_arn = aws_lb_target_group.nlb-target-group.arn
  target_id        = each.value
  port             = 6443

  depends_on = [aws_instance.manager-1, aws_instance.manager-peers]
}
