# Prumo — DevOps

*[Read in English](README.md)*

Infraestrutura e deploy do [Prumo](https://github.com/nickolascheidt/Prumo), um ERP
multi-tenant (API em .NET, SPA em [Angular](https://github.com/nickolascheidt/Prumo-Angular)):
Terraform para a AWS, uma stack Docker Compose para a máquina e os scripts que ligam uma
coisa à outra.

**Estado: desenhado e validado, nunca aplicado.** Todos os arquivos Terraform passam em
`fmt`/`validate` contra o provider real (o workflow `infra-check` roda os dois em pull
requests), mas o projeto parou antes de qualquer recurso ser criado numa conta AWS. Este
repo é o desenho, mantido como peça de portfólio.

## O desenho em um parágrafo

Uma instância Lightsail de 2 GB em `sa-east-1` roda quatro containers com
`docker compose`: Caddy (TLS), o nginx do Angular, a API e o PostgreSQL 17, com snapshot
diário, por cerca de US$ 14/mês. As imagens ficam no ECR, publicadas pelo GitHub Actions
por uma role de OIDC (sem chave da AWS guardada). O deploy é o `deploy/deploy.sh` por SSH,
a partir de uma estação de trabalho. O raciocínio e as trocas estão em
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), em inglês.

## História

A primeira versão rodou na Azure — Container Apps, ACR, Key Vault, PostgreSQL Flexible
Server — e funcionou ponta a ponta antes de ser derrubada. Ela migrou para este desenho na
AWS para trocar o preço de escalar a zero por uma conta fixa e pequena; o Terraform da
Azure continua no histórico do git.

## Licença

[MIT](LICENSE)
