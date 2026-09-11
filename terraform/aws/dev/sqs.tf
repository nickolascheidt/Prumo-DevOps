# Os números são os mesmos do elasticmq/elasticmq.conf no repo da aplicação, de
# propósito: o local não deve ser mais permissivo que o remoto.
resource "aws_sqs_queue" "notifications_dlq" {
  name = "${local.name}-notifications-dlq"
}

resource "aws_sqs_queue" "notifications" {
  name                       = "${local.name}-notifications"
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 5
  })
}
