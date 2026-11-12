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

# SonarQube (TASK-009): mesmo ALB interno, nova target group apontando pro
# NodePort fixo do Helm (sonarqube/values.yaml), roteada por path via regra
# de listener -- nao precisa de um novo VPC Link nem de uma nova integracao
# no API Gateway, so uma rota nova usando a integracao ANY /{proxy+} que ja
# existe (ver http_api.tf).
resource "aws_lb_target_group" "sonarqube" {
  name        = "${var.projectName}-sonar-tg"
  port        = 30900
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.base.id
  target_type = "instance"

  health_check {
    path                = "/sonarqube/api/system/status"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, {
    Name = "${var.projectName}-sonar-tg"
  })
}

resource "aws_lb_listener_rule" "sonarqube" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sonarqube.arn
  }

  condition {
    path_pattern {
      values = ["/sonarqube*"]
    }
  }
}

resource "aws_autoscaling_attachment" "sonarqube" {
  autoscaling_group_name = data.aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.sonarqube.arn
}

# ALB publico dedicado so ao SonarQube -- o scanner Maven baixa o scanner
# engine (~60-80MB) do host do Sonar a cada analise, e o limite de payload
# do API Gateway HTTP API (10MB, fixo, nao configuravel) sempre rejeitaria
# esse download. Usa o mesmo SG "alb" do infra-base, que ja libera 80/443
# de 0.0.0.0/0. Target group propria -- a AWS nao deixa a mesma target
# group ser associada a mais de um load balancer.
resource "aws_lb" "sonarqube_public" {
  name               = "${var.projectName}-sonar-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  tags = merge(var.tags, {
    Name = "${var.projectName}-sonar-alb"
  })
}

resource "aws_lb_target_group" "sonarqube_public" {
  name        = "${var.projectName}-sonar-pub-tg"
  port        = 30900
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.base.id
  target_type = "instance"

  health_check {
    path                = "/sonarqube/api/system/status"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, {
    Name = "${var.projectName}-sonar-pub-tg"
  })
}

resource "aws_lb_listener" "sonarqube_public" {
  load_balancer_arn = aws_lb.sonarqube_public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sonarqube_public.arn
  }
}

resource "aws_autoscaling_attachment" "sonarqube_public" {
  autoscaling_group_name = data.aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.sonarqube_public.arn
}

# Webhook do Mercado Pago (TASK-013) -- mesma mecanica das demais rotas por
# path neste ALB. O billing-service ainda nao existe (scaffold e TASK-032),
# mas a target group ja fica pronta apontando pro NodePort que o manifesto
# K8s do servico vai usar quando for criado (mesma convencao do nodePort
# fixo: 30080 app, 30900 sonarqube, 30084 billing-service).
resource "aws_lb_target_group" "billing" {
  name        = "${var.projectName}-billing-tg"
  port        = 30084
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
    Name = "${var.projectName}-billing-tg"
  })
}

resource "aws_lb_listener_rule" "billing_webhook" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.billing.arn
  }

  # /budgets/* (aprovar/recusar orcamento) -- rota autenticada, protegida
  # pelo authorizer JWT do API Gateway via ANY /{proxy+} (ver http_api.tf).
  # /webhooks/mercadopago continua publica, sem authorizer.
  condition {
    path_pattern {
      values = ["/webhooks/mercadopago", "/budgets/*"]
    }
  }
}

resource "aws_autoscaling_attachment" "billing" {
  autoscaling_group_name = data.aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.billing.arn
}

# core-service (TASK-017) -- substitui o monolito nesses paths (clientes,
# veiculos, ordens de servico, login de funcionario). O monolito fica
# obsoleto conforme a migracao avanca, por isso a regra de listener tem
# prioridade sobre o default (que ainda aponta pro app-tg do monolito).
resource "aws_lb_target_group" "core_service" {
  name        = "${var.projectName}-core-svc-tg"
  port        = 30081
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
    Name = "${var.projectName}-core-svc-tg"
  })
}

resource "aws_lb_listener_rule" "core_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.core_service.arn
  }

  # path_pattern aceita no maximo 5 valores por regra no ALB; "*" ja cobre
  # tanto o path exato quanto subpaths (ex: "/vehicles*" bate com "/vehicles"
  # e "/vehicles/abc"), entao nao precisa listar as duas formas separadas.
  condition {
    path_pattern {
      values = [
        "/auth/login",
        "/service-orders*",
        "/customers*",
        "/vehicles*",
        "/mechanical-hub/*",
      ]
    }
  }
}

resource "aws_autoscaling_attachment" "core_service" {
  autoscaling_group_name = data.aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.core_service.arn
}

# repair-service -- catalogo (servicos/materiais) e tarefas de execucao.
# Prioridade (25) menor que a do core-service (30) de proposito: sem isso,
# "/service-orders*" do core-service roubaria o trafego de
# "/service-orders/*/tasks*" antes dessa regra ser avaliada.
resource "aws_lb_target_group" "repair_service" {
  name        = "${var.projectName}-repair-svc-tg"
  port        = 30082
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
    Name = "${var.projectName}-repair-svc-tg"
  })
}

resource "aws_lb_listener_rule" "repair_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 25

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.repair_service.arn
  }

  condition {
    path_pattern {
      values = [
        "/materials*",
        "/services*",
        "/service-orders/*/tasks*",
      ]
    }
  }
}

resource "aws_autoscaling_attachment" "repair_service" {
  autoscaling_group_name = data.aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.repair_service.arn
}

# stock-service -- exige token com perfil ADMINISTRATOR (igual era /stock/**
# no monolito).
resource "aws_lb_target_group" "stock_service" {
  name        = "${var.projectName}-stock-svc-tg"
  port        = 30083
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
    Name = "${var.projectName}-stock-svc-tg"
  })
}

resource "aws_lb_listener_rule" "stock_service" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 26

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stock_service.arn
  }

  condition {
    path_pattern {
      values = ["/stock*"]
    }
  }
}

resource "aws_autoscaling_attachment" "stock_service" {
  autoscaling_group_name = data.aws_eks_node_group.node_group.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.stock_service.arn
}
