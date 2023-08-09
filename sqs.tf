terraform {
  required_providers {
    aws = "~> 3.79.0"
  }

  provider "aws" {
    region = "us-east-1"
  }

  resource "aws_sqs_queue" "my_queue1" {
    queue_name = "my-queue1"
  }
}
