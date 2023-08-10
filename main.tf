# Terraform Block
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Provider Block
provider "aws" {
  region  = "ap-south-1"
  access_key_id = var.aws_access_key_id
  secret_access_key = var.aws_secret_access_key
  profile = "default"
}

# Create EC2 Instance
resource "aws_instance" "my-ec2-vm" {
  ami               = "ami-079b5e5b3971bd10d"
  instance_type     = "t2.micro"
  availability_zone = "ap-south-1b"
  #availability_zone = "ap-south-1a"
  tags = {
    "Name" = "web"
    "tag1" = "Update-test-1"    
  }
}
