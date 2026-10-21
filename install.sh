#!/bin/sh
# install entrypoint, delegate to scripts/install.sh
set -eu

# shellcheck disable=SC1007
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$here/scripts/install.sh" "$@"
