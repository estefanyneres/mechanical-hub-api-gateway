data "aws_vpc" "base" {
  filter {
    name   = "tag:Name"
    values = [var.projectName]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.base.id]
  }

  tags = {
    Tier = "private"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.base.id]
  }

  tags = {
    Tier = "public"
  }
}

data "aws_security_group" "alb" {
  filter {
    name   = "tag:Name"
    values = ["${var.projectName}-alb-sg"]
  }
}

data "aws_eks_cluster" "cluster" {
  name = "eks-${var.projectName}"
}

data "aws_eks_node_group" "node_group" {
  cluster_name    = data.aws_eks_cluster.cluster.name
  node_group_name = "nodeg-${var.projectName}"
}

data "aws_lambda_function" "auth" {
  function_name = "${var.projectName}-auth"
}
