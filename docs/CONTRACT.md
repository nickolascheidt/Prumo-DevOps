# Contrato: repos de aplicação → este repo

Cada repo de aplicação constrói **uma** imagem e a empurra para o ECR, marcada com o SHA
do commit e com `latest`. **E para por aí.**

Na era Azure havia um `repository_dispatch` que disparava o deploy automático; **não há
mais**. O deploy do piloto é `deploy/deploy.sh`, rodado da máquina de quem publica, por
SSH. O motivo está no cabeçalho do script: o Lightsail não é alcançável por SSM Run
Command, e a alternativa seria abrir a porta 22 para o mundo e guardar uma chave privada
num secret do GitHub.

## Nomes de imagem

- API: `<ecr-registry>/prumo-api:<git-sha>` (e `:latest`)
- Frontend: `<ecr-registry>/prumo-web:<git-sha>` (e `:latest`)

O registry sai de `terraform output -raw ecr_registry` e tem a forma
`<account-id>.dkr.ecr.sa-east-1.amazonaws.com`.

## Secrets que os repos de aplicação precisam

Dois, os mesmos nos dois repos, ambos saindo de `terraform output` aqui (Task 10, Passo 1):

- `AWS_DEPLOY_ROLE_ARN` — a role assumida por OIDC, de `github_deploy_role_arn`. Não há
  chave de acesso guardada em secret.
- `ECR_REGISTRY` — de `ecr_registry`.

## Estado dos gatilhos

Os dois workflows estão em **`workflow_dispatch`** de propósito: sem ECR e sem secrets,
um gatilho por `push` deixaria a aba Actions vermelha a cada commit. Trocar para

```yaml
on:
  push:
    branches: [main]
```

é o Passo final da Task 10, depois que o `terraform apply` existir e os secrets estiverem
postos.
