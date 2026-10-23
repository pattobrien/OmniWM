#!/bin/sh
. ~/demo-v2/hooks/lib.sh
here=$(field .active_workspace.name)
there=$(field .workspace.name)
app=$(field .window.bundle_id)
msg="Kept you on workspace $here."
say "$msg ${app##*.} activated on $there."
echo "stay on $here" >&2
exit 2
