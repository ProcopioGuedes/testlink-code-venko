# TestLink Venko

Fork customizado do [TestLink Open Source](https://github.com/TestLinkOpenSourceTRMS/testlink-code) com adaptacoes da Venko, rodando via Docker.

---

## Indice

1. [Instalacao (testlink-venko com Docker)](#1-instalacao-testlink-venko-com-docker)
2. [Introducao](#2-introducao)
3. [Notas de Release / Configuracoes Criticas](#3-notas-de-release--configuracoes-criticas)
4. [Requisitos do Sistema](#4-requisitos-do-sistema)
5. [Upgrade e Migracao](#5-upgrade-e-migracao)
6. [Equipe TestLink](#6-equipe-testlink)
7. [Bugs, Reports e Feedback](#7-bugs-reports-e-feedback)
8. [Mudancas](#8-mudancas)

---

## 1. Instalacao (testlink-venko com Docker)

Este projeto utiliza **Docker** e **Docker Compose** para facilitar a instalacao em qualquer maquina.

### Pre-requisitos

- [Docker](https://docs.docker.com/get-docker/) instalado (versao 20+)
- [Docker Compose](https://docs.docker.com/compose/install/) instalado (versao 2+)
- Git instalado
- Porta **8080** disponivel na maquina

### Passo a passo

#### 1. Clone o repositorio

```bash
git clone https://github.com/ProcopioGuedes/testlink-code-venko.git
cd testlink-code-venko
```

#### 2. Crie os diretorios de dados persistentes

```bash
sudo mkdir -p /srv/testlink/config_db
sudo mkdir -p /srv/testlink/logs
sudo mkdir -p /srv/testlink/upload_area
sudo mkdir -p /srv/testlink/custom
sudo mkdir -p /srv/testlink/templates_c
```

#### 3. Suba os containers

```bash
docker compose up -d --build
```

O processo ira:
- Construir a imagem do TestLink a partir do `Dockerfile`
- Subir o banco de dados MariaDB
- Subir a aplicacao TestLink na porta 8080
- Subir o servico de backup automatico do banco

> **Aguarde cerca de 30-60 segundos** para o banco de dados inicializar antes de acessar.

#### 4. Acesse o TestLink

Abra o navegador e acesse:

```
http://<IP-DA-MAQUINA>:8080
```

Na primeira vez, o TestLink ira mostrar a tela de **instalacao/configuracao inicial**.

#### 5. Configure o banco de dados na tela de setup

Na tela de instalacao do TestLink, use as seguintes credenciais:

| Campo          | Valor      |
|----------------|------------|
| Database Type  | MySQL      |
| Database Host  | `db`       |
| Database Name  | `testlink` |
| Database User  | `root`     |
| Database Pass  | `root123`  |

Clique em **"Process TestLink Setup"** e aguarde a criacao das tabelas.

#### 6. Login inicial

Apos o setup, acesse com:

| Campo    | Valor    |
|----------|----------|
| Usuario  | `admin`  |
| Senha    | `admin`  |

> **Troque a senha do admin imediatamente apos o primeiro acesso/root/testlink-venko/README.md && head -5 /root/testlink-venko/README.md | cat -v*

### Estrutura de dados persistentes

Os dados ficam em `/srv/testlink/` na maquina host:

```
/srv/testlink/
|-- config_db/         # Configuracoes do banco
|-- config_db_inc.php  # Arquivo de configuracao gerado no setup
|-- custom/            # Personalizacoes (logo, CSS, etc.)
|-- logs/              # Logs da aplicacao
|-- templates_c/       # Cache de templates Smarty
|-- upload_area/       # Arquivos enviados pelos usuarios
```

### Comandos uteis

```bash
# Ver status dos containers
docker compose ps

# Ver logs da aplicacao
docker compose logs -f testlink

# Parar os containers
docker compose down

# Parar e remover volumes (APAGA OS DADOS DO BANCO)
docker compose down -v

# Reiniciar apenas a aplicacao
docker compose restart testlink

# Acessar o terminal da aplicacao
docker exec -it testlink_app bash

# Acessar o banco de dados
docker exec -it testlink_db mysql -uroot -proot123 testlink
```

### Backup automatico

O servico `db_backup` faz backup automatico do banco de dados a cada 2 horas.
Os backups ficam no volume `backup_data` e sao mantidos por 7 dias.

Para fazer um backup manual:

```bash
docker exec testlink_db mysqldump -uroot -proot123 testlink | gzip > backup_manual_$(date +%Y%m%d_%H%M).sql.gz
```

### Troubleshooting

**Problema:** Pagina em branco ou erro 500 ao acessar
**Solucao:** Aguarde mais tempo para o banco subir, ou verifique os logs: `docker compose logs db`

**Problema:** "Could not connect to database"
**Solucao:** Verifique se o container do banco esta saudavel: `docker compose ps`

**Problema:** Permissao negada nos diretorios `/srv/testlink/`
**Solucao:** `sudo chmod -R 777 /srv/testlink/`

---

## 2. Introducao

TestLink e um sistema web de gerenciamento de testes e execucao de testes.
Permite que equipes de qualidade criem e gerenciem requisitos e casos de teste,
organizem-nos em planos de teste e executem os testes rastreando os resultados dinamicamente.

TestLink e um projeto open source licenciado sob GPL. Todo o codigo-fonte esta
disponivel gratuitamente via [GitHub](https://github.com/TestLinkOpenSourceTRMS/testlink-code).

---

## 3. Notas de Release / Configuracoes Criticas

Consulte o arquivo `CHANGELOG` para notas detalhadas de cada versao.

---

## 4. Requisitos do Sistema

Para a versao Docker deste fork (testlink-venko):

- Docker 20+
- Docker Compose 2+
- 1GB RAM minimo (2GB recomendado)
- 5GB de espaco em disco

---

## 5. Upgrade e Migracao

Para atualizar para uma nova versao do testlink-venko:

```bash
git pull origin testlink_1_9_20_fixed
docker compose down
docker compose up -d --build
```

---

## 6. Equipe TestLink

Projeto original mantido pela comunidade TestLink.
Fork customizado pela equipe Venko.

---

## 7. Bugs, Reports e Feedback

Para problemas relacionados as customizacoes Venko, abra uma issue em:
https://github.com/ProcopioGuedes/testlink-code-venko/issues

Para problemas do TestLink original:
https://github.com/TestLinkOpenSourceTRMS/testlink-code/issues

---

## 8. Mudancas

Consulte o arquivo `CHANGELOG` para o historico completo de mudancas do TestLink original.

Para mudancas especificas da versao Venko, consulte os commits deste repositorio.
