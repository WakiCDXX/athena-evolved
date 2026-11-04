#!/bin/bash
# Athena Directive Injector - Sets high-level goals for the reasoning loop

DIRECTIVE_FILE="/opt/athena/state/current_directive.json"

if [ -z "$1" ]; then
    echo "Usage: athena_directive \"Your goal here\""
    exit 1
fi

DIRECTIVE="$1"
TIMESTAMP=$(date +%s)

echo "Injecting directive: $DIRECTIVE"

echo "{\"directive\": \"$DIRECTIVE\", \"timestamp\": $TIMESTAMP, \"status\": \"PENDING\"}" > "$DIRECTIVE_FILE"

echo "Directive accepted. The next reasoning cycle will incorporate this goal."
