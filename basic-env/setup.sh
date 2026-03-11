#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sh "$SCRIPT_DIR/docker/setup.sh"
sh "$SCRIPT_DIR/user/setup.sh"