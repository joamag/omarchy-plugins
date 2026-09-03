#!/bin/bash

# One snapshot of Docker state as tab-separated lines for the widget:
#
#   state      missing | stopped | denied | error | ok
#   error      message, only with state error
#   container  id  name  image  state  status  ports   (one per container)
#
# The socket permission is checked before docker runs so an account outside
# the docker group (Omarchy's default) gets a quiet "denied" instead of a CLI
# error every refresh.

set -o pipefail

if ! command -v docker >/dev/null 2>&1; then
  printf 'state\tmissing\n'
  exit 0
fi

sock="${OMARCHY_DOCKER_SOCKET:-/var/run/docker.sock}"
if [[ ! -S $sock ]]; then
  printf 'state\tstopped\n'
  exit 0
fi
if [[ ! -r $sock || ! -w $sock ]]; then
  printf 'state\tdenied\n'
  exit 0
fi

out=$(timeout 8 docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}\t{{.Status}}\t{{.Ports}}' 2>&1)
rc=$?
if (( rc != 0 )); then
  case "$out" in
    *"permission denied"*) printf 'state\tdenied\n' ;;
    *"Cannot connect"* | *"Is the docker daemon running"*) printf 'state\tstopped\n' ;;
    *) printf 'state\terror\nerror\t%s\n' "${out//$'\n'/ }" ;;
  esac
  exit 0
fi

printf 'state\tok\n'
while IFS= read -r line; do
  [[ -n $line ]] && printf 'container\t%s\n' "$line"
done <<<"$out"
