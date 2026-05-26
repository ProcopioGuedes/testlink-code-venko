#!/usr/bin/env bash
# Sincroniza o conteudo deste repositorio com /var/www/html no container TestLink,
# preservando volumes bind-mounted e metadados do projeto.
#
# Uso:
#   ./sync-to-container.sh                      # usa containers padrao (testlink_app/testlink_db)
#   ./sync-to-container.sh meu_app              # outro nome para o container do app
#   ./sync-to-container.sh meu_app meu_db       # outros nomes para app e db
#   FORCE_BROKEN=1 ./sync-to-container.sh       # ignora pre-flight (use so se souber o que faz)
#   NO_AUTO_SCHEMA=1 ./sync-to-container.sh     # desativa auto-carga do schema quando o DB esta vazio

set -euo pipefail

CONTAINER="${1:-testlink_app}"
DB_CONTAINER="${2:-testlink_db}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="/var/www/html"
APP_URL="${APP_URL:-http://localhost:8080/login.php}"
FORCE_BROKEN="${FORCE_BROKEN:-0}"
NO_AUTO_SCHEMA="${NO_AUTO_SCHEMA:-0}"

# Credenciais lidas de config_db.inc.php no app container. Preenchidas por
# read_db_creds() e reusadas tanto pela checagem quanto pela auto-recuperacao.
DB_USER=""
DB_PASS=""
DB_NAME=""
DB_HOST=""

err() { echo "$@" >&2; }

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  err "Erro: container '$CONTAINER' nao esta rodando."
  err "Suba os containers com: docker compose up -d"
  exit 1
fi

# ============================================================================
# PRE-FLIGHT: o sync escreve arquivos em /var/www/html mas NAO mexe no banco
# nem em volumes Docker. Se o container ja esta quebrado (ex: alguem rodou
# 'docker compose down -v' e perdeu o schema do banco), rodar o sync nao vai
# consertar - e ainda mascara o problema real. Checamos a saude antes para
# falhar cedo com uma mensagem clara, em vez de empurrar codigo num container
# corrompido.
# ============================================================================

read_db_creds() {
  # Le credenciais do config_db.inc.php dentro do container do app (e o que
  # o codigo PHP realmente usa). Fallback para os defaults do compose se nao
  # conseguir parsear. Idempotente - pode ser chamada varias vezes.
  local cfg
  cfg=$(docker exec "$CONTAINER" cat /var/www/html/config_db.inc.php 2>/dev/null || echo "")
  DB_USER=$(echo "$cfg" | sed -n "s/.*DB_USER'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  DB_PASS=$(echo "$cfg" | sed -n "s/.*DB_PASS'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  DB_NAME=$(echo "$cfg" | sed -n "s/.*DB_NAME'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  DB_HOST=$(echo "$cfg" | sed -n "s/.*DB_HOST'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  [ -z "$DB_USER" ] && DB_USER="root"
  [ -z "$DB_PASS" ] && DB_PASS="root123"
  [ -z "$DB_NAME" ] && DB_NAME="testlink"
  [ -z "$DB_HOST" ] && DB_HOST="db"
}

check_db_schema() {
  # Retorna 0 se o DB tem o schema do TestLink (tabela db_version existe),
  # 1 se o DB esta vazio ou inacessivel. Silenciosa - quem chama decide o que
  # fazer com o resultado.
  if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
    return 2  # container de DB nem existe, nao da pra checar
  fi
  read_db_creds
  local tables
  tables=$(docker exec "$DB_CONTAINER" sh -c \
    "mysql -h'$DB_HOST' -u'$DB_USER' -p'$DB_PASS' '$DB_NAME' -N -B -e 'SHOW TABLES LIKE \"db_version\";' 2>/dev/null" \
    | tr -d '[:space:]')
  [ "$tables" = "db_version" ]
}

auto_load_schema() {
  # Carrega o schema padrao do TestLink no DB e insere os dados default
  # (perfis, admin etc.). Equivalente ao "passo 2" das instrucoes manuais
  # de recuperacao, mas reusando as credenciais ja parseadas do config.
  local tables_sql="$SRC_DIR/install/sql/mysql/testlink_create_tables.sql"
  local data_sql="$SRC_DIR/install/sql/mysql/testlink_create_default_data.sql"
  if [ ! -f "$tables_sql" ] || [ ! -f "$data_sql" ]; then
    err "    [erro] SQLs nao encontrados em $SRC_DIR/install/sql/mysql/"
    return 1
  fi
  read_db_creds
  echo "    -> criando tabelas em '$DB_NAME' a partir de testlink_create_tables.sql"
  if ! docker exec -i "$DB_CONTAINER" \
        mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$tables_sql" 2> >(sed 's/^/        /' >&2); then
    err "    [erro] falha ao executar testlink_create_tables.sql"
    return 1
  fi
  echo "    -> inserindo dados default a partir de testlink_create_default_data.sql"
  if ! docker exec -i "$DB_CONTAINER" \
        mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$data_sql" 2> >(sed 's/^/        /' >&2); then
    err "    [erro] falha ao executar testlink_create_default_data.sql"
    return 1
  fi
  return 0
}

check_http_health() {
  # Retorna 0 se login.php responde 200 SEM o backtrace de DB Access Error.
  # 1 se o app esta servindo a pagina de erro. 2 se nao consegue alcancar.
  local body
  body=$(curl -fsS --max-time 5 "$APP_URL" 2>/dev/null) || return 2
  if echo "$body" | grep -q "DB Access Error - debug_print_backtrace"; then
    return 1
  fi
  return 0
}

echo "==> Pre-flight: checando saude atual do container"

db_ok=1
case "$(check_db_schema && echo ok || echo $?)" in
  ok) echo "    [ok] DB tem schema do TestLink" ;;
  2)  echo "    [aviso] container de DB '$DB_CONTAINER' nao encontrado, pulando checagem"; db_ok=0 ;;
  *)  err  "    [QUEBRADO] DB '$DB_CONTAINER' nao tem a tabela db_version"; db_ok=2 ;;
esac

http_ok=1
case "$(check_http_health && echo ok || echo $?)" in
  ok) echo "    [ok] $APP_URL responde sem DB Access Error" ;;
  1)  err  "    [QUEBRADO] $APP_URL esta servindo backtrace de DB Access Error"; http_ok=2 ;;
  *)  echo "    [aviso] nao consegui alcancar $APP_URL, pulando checagem HTTP"; http_ok=0 ;;
esac

# ----------------------------------------------------------------------------
# Auto-recuperacao: se o DB esta sem o schema do TestLink, em vez de abortar
# e pedir que o usuario rode os SQLs na mao, carregamos automaticamente os
# scripts oficiais do install/. Depois reavaliamos o estado e seguimos com o
# sync se ficou bom. NO_AUTO_SCHEMA=1 desativa esse comportamento (volta a
# abortar como antes); FORCE_BROKEN=1 ignora tudo e empurra o sync mesmo
# assim (so use se estiver preparando codigo antes de rodar o instalador).
# ----------------------------------------------------------------------------
if [ "$db_ok" = "2" ] && [ "$NO_AUTO_SCHEMA" != "1" ] && [ "$FORCE_BROKEN" != "1" ]; then
  echo ""
  echo "==> Auto-recuperacao: DB sem schema, tentando carregar automaticamente"
  if auto_load_schema && check_db_schema; then
    echo "    [ok] schema carregado e tabela db_version presente"
    db_ok=1
    # O HTTP pode ter destravado agora que o DB tem schema - reavalia.
    case "$(check_http_health && echo ok || echo $?)" in
      ok) echo "    [ok] $APP_URL agora responde sem DB Access Error"; http_ok=1 ;;
      1)  err "    [QUEBRADO] $APP_URL ainda serve backtrace apos a carga"; http_ok=2 ;;
      *)  echo "    [aviso] nao consegui alcancar $APP_URL apos a carga"; http_ok=0 ;;
    esac
  else
    err "    [erro] auto-recuperacao falhou - schema continua ausente"
  fi
fi

if [ "$db_ok" = "2" ] || [ "$http_ok" = "2" ]; then
  err ""
  err "================================================================"
  err "ABORTANDO: o container ja esta em estado quebrado ANTES do sync."
  err ""
  err "O sync apenas copia arquivos PHP - nao recria tabelas do banco."
  err "Sintomas tipicos desse estado:"
  err "  - alguem rodou 'docker compose down -v' (a flag -v apaga volumes)"
  err "  - o volume 'db_data' foi removido manualmente"
  err "  - o banco nunca foi inicializado pelo instalador"
  err ""
  if [ "$NO_AUTO_SCHEMA" = "1" ]; then
    err "NO_AUTO_SCHEMA=1 esta setado - a auto-recuperacao foi pulada."
    err ""
  fi
  err "Como recuperar:"
  err "  1) Abra http://localhost:8080/install/index.php no navegador e"
  err "     siga o instalador para recriar o schema, OU"
  err "  2) Carregue o schema manualmente:"
  err "     docker exec -i $DB_CONTAINER mysql -uroot -proot123 testlink \\"
  err "       < install/sql/mysql/testlink_create_tables.sql"
  err "     docker exec -i $DB_CONTAINER mysql -uroot -proot123 testlink \\"
  err "       < install/sql/mysql/testlink_create_default_data.sql"
  err ""
  err "Se voce TEM CERTEZA que quer sincronizar mesmo assim (ex: esta"
  err "preparando o codigo antes de rodar o instalador), use:"
  err "  FORCE_BROKEN=1 $0 $*"
  err "================================================================"
  if [ "$FORCE_BROKEN" != "1" ]; then
    exit 3
  fi
  err ""
  err "FORCE_BROKEN=1 setado - prosseguindo apesar do estado quebrado."
fi

# ============================================================================
# Lint de sanidade: roda 'php -l' nos arquivos que, se quebrados, derrubam
# a aplicacao inteira. Empurrar PHP com syntax error pra dentro do container
# ja causou outage uma vez (locale/en_GB/strings.txt corrompido) - melhor
# falhar aqui do que no navegador.
# ============================================================================
lint_files=()
while IFS= read -r -d '' f; do lint_files+=("$f"); done < <(find "$SRC_DIR" -maxdepth 1 -type f -name '*.php' -print0)
while IFS= read -r -d '' f; do lint_files+=("$f"); done < <(find "$SRC_DIR/locale" -mindepth 2 -maxdepth 2 -type f -name 'strings.txt' -print0 2>/dev/null)

echo "==> Validando sintaxe PHP de ${#lint_files[@]} arquivos criticos"
fail=0
for f in "${lint_files[@]}"; do
  if ! out=$(docker exec -i "$CONTAINER" php -l 2>&1 < "$f"); then
    rel="${f#$SRC_DIR/}"
    # Se o container ja tem o mesmo arquivo (md5 identico), o sync e no-op
    # para este arquivo - pode ser bug upstream pre-existente. Avisa mas nao bloqueia.
    host_md5=$(md5sum "$f" | awk '{print $1}')
    container_md5=$(docker exec "$CONTAINER" md5sum "/var/www/html/$rel" 2>/dev/null | awk '{print $1}')
    if [ -n "$container_md5" ] && [ "$host_md5" = "$container_md5" ]; then
      echo "    [aviso] $rel: parse error, mas identico ao container (status quo)"
    else
      err  "    [BLOQUEIA] $rel: parse error e diferente do container"
      echo "$out" | sed 's/^/        /' >&2
      fail=1
    fi
  fi
done
if [ $fail -ne 0 ]; then
  err "Erro: o sync introduziria novos arquivos PHP quebrados no container."
  err "Corrija os arquivos no host e rode novamente."
  exit 2
fi

# Paths que NAO devem ser sobrescritos:
#   - bind-mounts declarados no docker-compose.yml (ja apontam para /srv/testlink/*)
#   - arquivos de versionamento / configuracao de build do projeto
#   - artefatos pesados que nao precisam estar dentro do container
EXCLUDES=(
  --exclude=./.git
  --exclude=./.gitignore
  --exclude=./1.9.20.tar.gz
  --exclude=./upload_area
  --exclude=./logs
  --exclude=./custom
  --exclude=./config_db
  --exclude=./config_db.inc.php
  --exclude=./gui/templates_c
  --exclude=./Dockerfile
  --exclude=./docker-compose.yml
  --exclude=./docker-entrypoint.sh
  --exclude=./sync-to-container.sh
)

echo "==> Empacotando $SRC_DIR (excluindo bind-mounts e metadados)"
echo "==> Extraindo dentro de $CONTAINER:$DEST_DIR"
tar -C "$SRC_DIR" -cf - "${EXCLUDES[@]}" . \
  | docker exec -i "$CONTAINER" tar -C "$DEST_DIR" --no-same-owner -xf -

echo "==> Ajustando ownership dos arquivos top-level para www-data"
# Limitamos a profundidade 1 de proposito: o chown -R em /var/www/html inteiro
# satura o journal do ext4 e trava o entrypoint por minutos. Como o Apache so
# precisa de read (e os arquivos saem do tar como 644), isso e suficiente.
docker exec "$CONTAINER" sh -c \
  "find $DEST_DIR -maxdepth 1 -type f -exec chown www-data:www-data {} +"

# ============================================================================
# POST-FLIGHT: confirma que o sync nao regrediu o estado do app. Se antes do
# sync o HTTP estava saudavel e agora nao esta, o sync introduziu uma
# regressao - avisamos alto para que o usuario nao descubra so no navegador.
# ============================================================================
echo "==> Pos-flight: confirmando que o app continua respondendo"
sleep 1  # da tempo do Apache reler arquivos sobrescritos
case "$(check_http_health && echo ok || echo $?)" in
  ok)
    echo "    [ok] $APP_URL continua respondendo sem DB Access Error"
    ;;
  1)
    err "    [REGRESSAO] $APP_URL agora serve backtrace de DB Access Error."
    err "    O sync pode ter sobrescrito algum arquivo critico OU o banco"
    err "    perdeu o schema enquanto o sync rodava. Verifique:"
    err "      docker exec $DB_CONTAINER mysql -uroot -proot123 testlink -e 'SHOW TABLES;'"
    exit 4
    ;;
  *)
    err "    [aviso] nao consegui alcancar $APP_URL no pos-flight"
    ;;
esac

echo "==> Sync concluido."
echo "    Se voce alterou templates Smarty, limpe o cache:"
echo "    sudo rm -rf /srv/testlink/templates_c/*"
