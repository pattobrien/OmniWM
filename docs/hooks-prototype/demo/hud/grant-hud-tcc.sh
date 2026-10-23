#!/usr/bin/env bash
set -euo pipefail

HUD="${1:?usage: grant-hud-tcc.sh <absolute path to hud>}"
DB="/Library/Application Support/com.apple.TCC/TCC.db"

for service in kTCCServiceAccessibility kTCCServicePostEvent; do
  sudo sqlite3 "$DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, last_modified) VALUES ('$service', '$HUD', 1, 2, 4, 1, NULL, 0, CAST(strftime('%s','now') AS INTEGER));"
done

sudo sqlite3 "$DB" "SELECT service, client, client_type, auth_value, csreq IS NULL FROM access WHERE client = '$HUD';"
