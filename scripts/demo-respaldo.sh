#!/usr/bin/env bash
# Demo del respaldo de configuracion de FRR (playbook 05).
#
# Uso (Linux, macOS o WSL), desde cualquier carpeta:
#   ./scripts/demo-respaldo.sh              # resumen
#   ./scripts/demo-respaldo.sh --detalle    # ademas, la salida completa de Ansible
#
# En Windows usar scripts/demo-respaldo.ps1 (llama a este script dentro de WSL).
#
# Requisitos: Docker con el laboratorio levantado (routers arriba) y ansible-playbook.
# No modifica nada del repo salvo crear los respaldos en backups/frr/.
set -u

DETALLE=0
case "${1:-}" in
  --detalle|-d) DETALLE=1 ;;
  -h|--help) sed -n '2,12p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "Opcion desconocida: $1 (usar --detalle o --help)"; exit 2 ;;
esac

REPO="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FECHA="$(date +%Y-%m-%d)"
ROUTERS="router-a router-b router-c"

if [ -t 1 ]; then V=$'\033[32m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'; else V=""; R=""; C=""; N=""; fi
titulo() { printf '\n%s== %s%s\n' "$C" "$1" "$N"; }
falla()  { printf '\n%sERROR: %s%s\n' "$R" "$1" "$N"; exit 1; }
ok()     { printf '%s%s%s\n' "$V" "$1" "$N"; }

titulo "1/4 Comprobando el entorno"
command -v docker >/dev/null 2>&1 || falla "No encuentro 'docker'. Instalar Docker (o abrir Docker Desktop)."
docker ps >/dev/null 2>&1 || falla "Docker no responde. Abrir Docker Desktop / iniciar el servicio y reintentar."
ACTIVOS="$(docker ps --format '{{.Names}}')"
for r in $ROUTERS; do
  printf '%s\n' "$ACTIVOS" | grep -qx "$r" || falla "El contenedor $r no esta corriendo. Levantar el laboratorio: docker compose -f demo/docker-compose.yml up -d"
done
ok "Docker OK, routers arriba: $(echo $ROUTERS | sed 's/ /, /g')"
command -v ansible-playbook >/dev/null 2>&1 || falla "No encuentro 'ansible-playbook'. En Ubuntu/WSL: sudo apt-get install -y ansible-core"
ok "Ansible disponible: $(ansible --version 2>/dev/null | head -1)"

titulo "2/4 Ejecutando el playbook 05-backup-configs.yml"
SALIDA="$(cd /tmp && ANSIBLE_CONFIG="$REPO/ansible/ansible.cfg" ANSIBLE_NOCOLOR=1 \
  ansible-playbook -i "$REPO/ansible/inventory/hosts.yml" "$REPO/ansible/playbooks/05-backup-configs.yml" 2>&1)"
CODIGO=$?
[ "$DETALLE" -eq 1 ] && printf '%s\n' "$SALIDA"
printf '%s\n' "$SALIDA" | grep -E '^controlador +:' | head -1
if [ "$CODIGO" -ne 0 ]; then
  printf '\n'; printf '%s\n' "$SALIDA" | tail -15
  falla "El playbook termino con errores (codigo $CODIGO). Ejecutar con --detalle para ver la salida completa."
fi
ok "Playbook OK"

titulo "3/4 Respaldos generados en backups/frr"
printf '%-9s %-26s %6s %7s %8s %s\n' Router Archivo Bytes "AS BGP" Vecinos Valido
TODOS_OK=1
for r in $ROUTERS; do
  F="$REPO/backups/frr/$r-$FECHA.cfg"
  if [ -f "$F" ]; then
    BYTES="$(wc -c < "$F" | tr -d ' ')"
    ASN="$(sed -n 's/^router bgp \([0-9][0-9]*\).*/\1/p' "$F" | head -1)"
    VEC="$(grep -cE '^ *neighbor [^ ]+ remote-as [0-9]+' "$F")"
    if [ -n "$ASN" ] && [ "$VEC" -gt 0 ]; then VAL="OK"; else VAL="NO"; TODOS_OK=0; fi
    printf '%-9s %-26s %6s %7s %8s %s\n' "$r" "$r-$FECHA.cfg" "$BYTES" "$ASN" "$VEC" "$VAL"
  else
    printf '%-9s %-26s %6s %7s %8s %s\n' "$r" "(no generado)" 0 - 0 NO; TODOS_OK=0
  fi
done

titulo "4/4 Resultado"
if [ "$TODOS_OK" -eq 1 ]; then
  ok "RESPALDO COMPLETO: 3 routers respaldados y validados (router bgp + neighbor)."
  echo "Ver un respaldo:  cat backups/frr/router-a-$FECHA.cfg"
else
  falla "Algun respaldo no es valido. Revisar la tabla de arriba."
fi
