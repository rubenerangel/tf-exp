terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_ssm_parameter" "a" {
  name  = "/exp/a"
  type  = "String"
  value = "hola-4"
}

resource "aws_ssm_parameter" "b" {
  name  = "/exp/b"
  type  = "String"
  value = "mundo"
}