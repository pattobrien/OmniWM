PATH=/Users/runner/demo-v2/bin:/opt/homebrew/bin:$PATH
PROMPT='%F{cyan}$%f '
printf '\033]0;%s\007' "$DEMO_TITLE"
clear
[ -n "$DEMO_TEXT" ] && cat "$DEMO_TEXT"
