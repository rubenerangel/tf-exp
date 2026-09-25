variable "state_bucket" {
  default = "tfstate-ruben-20260923"
}

terraform {
  backend "s3" {
    
    region       = "us-east-1"
    use_lockfile = true
    encrypt = true
  }
}