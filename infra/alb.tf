resource "aws_lb" "internal" {
  name               = "${var.projectName}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.alb.id]
  subnets            = data.aws_subnets.private.ids

  tags = merge(var.tags, {
    Name = "${var.projectName}-alb"
  })
}

resource "aws_lb_target_group" "app" {
  name        = "${var.projectName}-app-tg"
  port        = 30080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.base.id
  target_type = "instance"

  health_check {
    path                = "/actuator/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, {
    Name = "${var.projectName}-app-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_autoscaling_attachment" "node_group" {
  autoscaling_group_name = data.aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.app.arn
}
