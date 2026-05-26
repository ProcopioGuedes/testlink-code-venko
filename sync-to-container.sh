#!/usr/bin/env bash
# Sincroniza o conteudo deste repositorio com /var/www/html no container TestLink,
# preservando volumes bind-mounted e metadados do projeto.
#
# Uso:
#   ./sync-to-container.sh                 # usa o container 'testlink_app'
#   ./sync-to-container.sh meu_container   # usa outro nome de container

set -euo pipefail

CONTAINER="${1:-testlink_app}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="/var/www/html"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Erro: container '$CONTAINER' nao esta rodando." >&2
  echo "Suba os containers com: docker compose up -d" >&2
  exit 1
fi

# Lint de sanidade: roda 'php -l' nos arquivos que, se quebrados, derrubam
# a aplicacao inteira. Empurrar PHP com syntax error pra dentro do container
# ja causou outage uma vez (locale/en_GB/strings.txt corrompido) - melhor
# falhar aqui do que no navegador.
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
      echo "    [BLOQUEIA] $rel: parse error e diferente do container" >&2
      echo "$out" | sed 's/^/        /' >&2
      fail=1
    fi
  fi
done
if [ $fail -ne 0 ]; then
  echo "Erro: o sync introduziria novos arquivos PHP quebrados no container." >&2
  echo "Corrija os arquivos no host e rode novamente." >&2
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

echo "==> Sync concluido."
echo "    Se voce alterou templates Smarty, limpe o cache:"
echo "    sudo rm -rf /srv/testlink/templates_c/*"
