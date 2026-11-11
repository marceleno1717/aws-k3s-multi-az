# App Load Balancer

resource "aws_security_group" "alb-sg" {
  name   = "alb-sg"
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
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
  }
}


resource "aws_lb" "k3s-alb" {
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
  load_balancer_type               = "application"
  security_groups                  = [aws_security_group.alb-sg.id]
  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "alb-target-group" {
  vpc_id      = aws_vpc.k3s.id
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"

  health_check {
    enabled             = true
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.k3s-alb.arn
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-target-group.arn
  }
}

resource "aws_lb_target_group_attachment" "alb-target-attachment" {
  for_each = aws_instance.workers

  target_group_arn = aws_lb_target_group.alb-target-group.arn
  target_id        = each.value.id
  port             = 80

  depends_on = [aws_instance.manager-1, aws_instance.manager-peers]
}

output "alb-dns" {
  value = aws_lb.k3s-alb.dns_name
}
