#!/bin/sh

set -e
SRCDIR="$(dirname $0)"
cd "${SRCDIR}"
autoreconf --install --force
