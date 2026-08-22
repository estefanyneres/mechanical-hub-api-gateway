variable "projectName" {
  default = "mechanical-hub"
}

variable "region_default" {
  default = "us-east-1"
}

variable "aws_account_id" {
  description = "ID da conta AWS Academy (muda a cada bimestre da pos-graduacao)"
  type        = string
}

variable "jwt_secret" {
  description = "Segredo usado para validar o JWT no authorizer (mesmo valor do repo da aplicacao e da Lambda de autenticacao)"
  type        = string
  sensitive   = true
}

variable "enable_authorizer" {
  description = "Se false, a rota ANY /{proxy+} fica sem authorizer (uso: testar o roteamento antes de acrescentar a validacao JWT)"
  type        = bool
  default     = true
}

variable "tags" {
  default = {
    School      = "FIAP"
    Environment = "Production"
  }
}

locals {
  labRole = "arn:aws:iam::${var.aws_account_id}:role/LabRole"
}
