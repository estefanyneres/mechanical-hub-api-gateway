output "api_endpoint" {
  description = "URL publica do HTTP API"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "alb_dns_name" {
  description = "DNS interno do ALB"
  value       = aws_lb.internal.dns_name
}

output "sonarqube_alb_dns_name" {
  description = "DNS publico do ALB dedicado ao SonarQube (usar em SONAR_HOST_URL)"
  value       = aws_lb.sonarqube_public.dns_name
}

output "authorizer_function_name" {
  description = "Nome da funcao Lambda do authorizer"
  value       = aws_lambda_function.authorizer.function_name
}
