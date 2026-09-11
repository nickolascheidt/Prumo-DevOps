# Sem `thumbprint_list`: para GitHub, GitLab, Google e Auth0 a AWS valida pela
# própria biblioteca de CAs raiz e ignora thumbprint configurado.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringLike, e não StringEquals: o `sub` carrega a ref do commit, então o
    # sufixo varia a cada execução.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in var.github_repos : "repo:${r}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${local.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

data "aws_iam_policy_document" "github_deploy" {
  # Empurrar imagem para os dois repositórios do ECR.
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      aws_ecr_repository.api.arn,
      aws_ecr_repository.web.arn,
    ]
  }

  # O token de login do ECR não aceita recurso específico.
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # E nada mais. Na versão EC2 deste plano havia aqui permissão de
  # `ssm:SendCommand` para disparar o deploy na instância; o Lightsail não é
  # alcançável por SSM Run Command, então o deploy vira SSH (Task 10) e esta role
  # passa a fazer só uma coisa: empurrar imagem.
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
