resource "aws_sqs_queue" "my_queue" {
  name = "my-queue"
  visibility_timeout = 30
  max_receive_count = 10
}
