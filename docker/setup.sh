#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sh "$SCRIPT_DIR/traefik/setup.sh"
sh "$SCRIPT_DIR/mongodb/setup.sh"
sh "$SCRIPT_DIR/postgres/setup.sh"
