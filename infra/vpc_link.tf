resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.projectName}-vpc-link"
  security_group_ids = [data.aws_security_group.alb.id]
  subnet_ids         = data.aws_subnets.private.ids

  tags = merge(var.tags, {
    Name = "${var.projectName}-vpc-link"
  })
}
