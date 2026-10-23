#!/bin/sh
. ~/demo-v2/hooks/lib.sh
say "Hook: '$(field .window.title)' goes to logs"
echo '{"workspace": "3"}'
