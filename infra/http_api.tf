resource "aws_apigatewayv2_api" "this" {
  name          = "${var.projectName}-api"
  protocol_type = "HTTP"

  tags = merge(var.tags, {
    Name = "${var.projectName}-api"
  })
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  tags = var.tags
}

# Rota curinga para a aplicacao (via ALB interno / VPC Link)

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.http.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = var.enable_authorizer ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_authorizer ? aws_apigatewayv2_authorizer.jwt.id : null
}

# Rotas publicas da aplicacao (permitAll no SecurityConfiguration.java) -- precisam
# ficar fora do authorizer, senao o proxy curinga acima as engoliria e ninguem
# consegue nem logar.
#
# "/mechanical-hub/service-orders/**" NAO entra aqui de proposito: hoje esta
# permitAll() na aplicacao (nao existia autenticacao de cliente ainda), mas com a
# Lambda de CPF deve passar a exigir o JWT do cliente -- cai no ANY /{proxy+}
# protegido pelo authorizer. Pendente ajuste correspondente no SecurityConfiguration
# da aplicacao (proxima atividade).
locals {
  app_public_routes = [
    "POST /auth/login",
    "GET /actuator/health",
    "ANY /swagger-ui/{proxy+}",
    "ANY /v3/api-docs/{proxy+}",
  ]
}

resource "aws_apigatewayv2_route" "app_public" {
  for_each = toset(local.app_public_routes)

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# Rota publica para a Lambda de autenticacao de clientes (emite o token, nao pode exigir um)

resource "aws_apigatewayv2_integration" "auth_lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = data.aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth_cpf" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /auth/cpf"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_lambda_permission" "apigw_invoke_auth" {
  statement_id  = "AllowAPIGatewayInvokeAuth"
  action        = "lambda:InvokeFunction"
  function_name = data.aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*"
}
