# O preço de ter escolhido Lightsail: sem instance profile, a máquina precisa de
# uma credencial gravada em disco para falar com a AWS. A defesa é dar a essa
# credencial o menor poder possível, e é isso que este arquivo faz.
resource "aws_iam_user" "box" {
  name = "${local.name}-box"
}

data "aws_iam_policy_document" "box" {
  # Enfileirar notificação. É a única escrita que a máquina faz na AWS.
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.notifications.arn]
  }

  # Puxar as imagens. Só leitura, e só destes dois repositórios.
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [aws_ecr_repository.api.arn, aws_ecr_repository.web.arn]
  }

  # O token de login do ECR não aceita recurso específico.
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "box" {
  name   = "runtime"
  user   = aws_iam_user.box.name
  policy = data.aws_iam_policy_document.box.json
}

# NÃO existe aws_iam_access_key aqui, e é de propósito: o Terraform guardaria a
# chave secreta em texto claro no state file. Ela é criada uma vez, à mão:
#
#     aws iam create-access-key --user-name prumo-dev-box
#
# O que um vazamento dessa chave dá ao atacante, na íntegra: enfileirar mensagens
# na fila de notificação e baixar as imagens de container. Não dá para ler
# segredo, criar recurso nem mexer na instância. É pequeno e limitado — mas não é
# zero, e na versão EC2 era zero. Se um dia isso incomodar, é o motivo certo para
# voltar para EC2.
