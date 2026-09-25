terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "param_prefix" {
  type    = string
  default = "/exp"
}

resource "aws_ssm_parameter" "a" {
  name  = "${var.param_prefix}/a"
  type  = "String"
  value = "hola-ci"
}

resource "aws_ssm_parameter" "b" {
  name  = "${var.param_prefix}/b"
  type  = "String"
  value = "mundo"
}