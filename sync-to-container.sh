#!/usr/bin/env bash
# Sincroniza o conteudo deste repositorio com /var/www/html no container TestLink,
# preservando volumes bind-mounted e metadados do projeto.
#
# Uso:
#   ./sync-to-container.sh                      # usa containers padrao (testlink_app/testlink_db)
#   ./sync-to-container.sh meu_app              # outro nome para o container do app
#   ./sync-to-container.sh meu_app meu_db       # outros nomes para app e db
#   FORCE_BROKEN=1 ./sync-to-container.sh       # ignora pre-flight (use so se souber o que faz)

set -euo pipefail

CONTAINER="${1:-testlink_app}"
DB_CONTAINER="${2:-testlink_db}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="/var/www/html"
APP_URL="${APP_URL:-http://localhost:8080/login.php}"
FORCE_BROKEN="${FORCE_BROKEN:-0}"

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

check_db_schema() {
  # Retorna 0 se o DB tem o schema do TestLink (tabela db_version existe),
  # 1 se o DB esta vazio ou inacessivel. Silenciosa - quem chama decide o que
  # fazer com o resultado.
  if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
    return 2  # container de DB nem existe, nao da pra checar
  fi
  # Le credenciais do config_db.inc.php dentro do container do app (e o que
  # o codigo PHP realmente usa). Fallback para variaveis do compose se nao
  # conseguir parsear.
  local cfg user pass db host
  cfg=$(docker exec "$CONTAINER" cat /var/www/html/config_db.inc.php 2>/dev/null || echo "")
  user=$(echo "$cfg" | sed -n "s/.*DB_USER'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  pass=$(echo "$cfg" | sed -n "s/.*DB_PASS'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  db=$(echo   "$cfg" | sed -n "s/.*DB_NAME'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  host=$(echo "$cfg" | sed -n "s/.*DB_HOST'[^,]*,[[:space:]]*'\([^']*\)'.*/\1/p" | head -1)
  [ -z "$user" ] && user="root"
  [ -z "$pass" ] && pass="root123"
  [ -z "$db" ]   && db="testlink"
  [ -z "$host" ] && host="db"

  local tables
  tables=$(docker exec "$DB_CONTAINER" sh -c \
    "mysql -h'$host' -u'$user' -p'$pass' '$db' -N -B -e 'SHOW TABLES LIKE \"db_version\";' 2>/dev/null" \
    | tr -d '[:space:]')
  [ "$tables" = "db_version" ]
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
