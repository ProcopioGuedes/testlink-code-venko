# TestLink Venko

Fork customizado do [TestLink Open Source](https://github.com/TestLinkOpenSourceTRMS/testlink-code) com adaptaes da Venko, rodando via Docker.

---

## ndice

1. [Instalao (testlink-venko com Docker)](#1-instalao-testlink-venko-com-docker)
2. [Introduo](#2-introduo)
3. [Notas de Release / Configuraes Crticas](#3-notas-de-release--configuraes-crticas)
4. [Requisitos do Sistema](#4-requisitos-do-sistema)
5. [Upgrade e Migrao](#5-upgrade-e-migrao)
6. [Equipe TestLink](#6-equipe-testlink)
7. [Bugs, Reports e Feedback](#7-bugs-reports-e-feedback)
8. [Mudanas](#8-mudanas)

---

## 1. Instalao (testlink-venko com Docker)

Este projeto utiliza **Docker** e **Docker Compose** para facilitar a instalao em qualquer mquina.

### Pr-requisitos

- [Docker](https://docs.docker.com/get-docker/) instalado (verso 20+)
- [Docker Compose](https://docs.docker.com/compose/install/) instalado (verso 2+)
- Git instalado
- Porta **8080** disponvel na mquina

### Passo a passo

#### 1. Clone o repositrio

```bash
git clone https://github.com/ProcopioGuedes/testlink-code-venko.git
cd testlink-code-venko
```

#### 2. Crie os diretrios de dados persistentes

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

O processo ir:
- Construir a imagem do TestLink a partir do `Dockerfile`
- Subir o banco de dados MariaDB
- Subir a aplicao TestLink na porta 8080
- Subir o servio de backup automtico do banco

> **Aguarde cerca de 30-60 segundos** para o banco de dados inicializar antes de acessar.

#### 4. Acesse o TestLink

Abra o navegador e acesse:

```
http://<IP-DA-MAQUINA>:8080
```

Na primeira vez, o TestLink ir mostrar a tela de **instalao/configurao inicial**.

#### 5. Configure o banco de dados na tela de setup

Na tela de instalao do TestLink, use as seguintes credenciais:

| Campo          | Valor      |
|----------------|------------|
| Database Type  | MySQL      |
| Database Host  | `db`       |
| Database Name  | `testlink` |
| Database User  | `root`     |
| Database Pass  | `root123`  |

Clique em **"Process TestLink Setup"** e aguarde a criao das tabelas.

#### 6. Login inicial

Aps o setup, acesse com:

| Campo    | Valor    |
|----------|----------|
| Usurio  | `admin`  |
| Senha    | `admin`  |

> ** Troque a senha do admin imediatamente aps o primeiro acesso!**

### Estrutura de dados persistentes

Os dados ficam em `/srv/testlink/` na mquina host:

```
/srv/testlink/
 config_db/         # Configuraes do banco
 config_db_inc.php  # Arquivo de configurao gerado no setup
 custom/            # Personalizaes (logo, CSS, etc.)
 logs/              # Logs da aplicao
 templates_c/       # Cache de templates Smarty
 upload_area/       # Arquivos enviados pelos usurios
```

### Comandos teis

```bash
# Ver status dos containers
docker compose ps

# Ver logs da aplicao
docker compose logs -f testlink

# Parar os containers
docker compose down

# Parar e remover volumes (APAGA OS DADOS DO BANCO)
docker compose down -v

# Reiniciar apenas a aplicao
docker compose restart testlink

# Acessar o terminal da aplicao
docker exec -it testlink_app bash

# Acessar o banco de dados
docker exec -it testlink_db mysql -uroot -proot123 testlink
```

### Backup automtico

O servio `db_backup` faz backup automtico do banco de dados a cada 2 horas.
Os backups ficam no volume `backup_data` e so mantidos por 7 dias.

Para fazer um backup manual:

```bash
docker exec testlink_db mysqldump -uroot -proot123 testlink | gzip > backup_manual_$(date +%Y%m%d_%H%M).sql.gz
```

### Troubleshooting

**Problema:** Pgina em branco ou erro 500 ao acessar  
**Soluo:** Aguarde mais tempo para o banco subir, ou verifique os logs: `docker compose logs db`

**Problema:** "Could not connect to database"  
**Soluo:** Verifique se o container do banco est saudvel: `docker compose ps`

**Problema:** Permisso negada nos diretrios `/srv/testlink/`  
**Soluo:** `sudo chmod -R 777 /srv/testlink/`

---

## 2. Introduo

TestLink  um sistema web de gerenciamento de testes e execuo de testes.
Permite que equipes de qualidade criem e gerenciem requisitos e casos de teste,
organizem-nos em planos de teste e executem os testes rastreando os resultados dinamicamente.

TestLink  um projeto open source licenciado sob GPL. Todo o cdigo-fonte est
disponvel gratuitamente via [GitHub](https://github.com/TestLinkOpenSourceTRMS/testlink-code).

---

## 3. Notas de Release / Configuraes Crticas

Consulte o arquivo `CHANGELOG` para notas detalhadas de cada verso.

---

## 4. Requisitos do Sistema

Para a verso Docker deste fork (testlink-venko):

- Docker 20+
- Docker Compose 2+
- 1GB RAM mnimo (2GB recomendado)
- 5GB de espao em disco

---

## 5. Upgrade e Migrao

Para atualizar para uma nova verso do testlink-venko:

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

Para problemas relacionados s customizaes Venko, abra uma issue em:
https://github.com/ProcopioGuedes/testlink-code-venko/issues

Para problemas do TestLink original:
https://github.com/TestLinkOpenSourceTRMS/testlink-code/issues

---

## 8. Mudanas

Consulte o arquivo `CHANGELOG` para o histrico completo de mudanas do TestLink original.

Para mudanas especficas da verso Venko, consulte os commits deste repositrio.
