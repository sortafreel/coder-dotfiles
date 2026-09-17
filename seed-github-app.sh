#!/usr/bin/env bash
# Seed this box's database for ReviewHog runs: the dev fixtures (team 1, user test@posthog.com), the dev
# personal API key with the gateway scope, and the GitHub App installation row for team 1.
# Needs the stack up (migrations done) and the GITHUB_APP_* secrets. Idempotent; rerun after `hogli nuke`.
set -euo pipefail

export INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-160555986}"
cd "$HOME/posthog"
[ -n "${GITHUB_APP_PRIVATE_KEY:-}" ] || { echo "GITHUB_APP_PRIVATE_KEY secret missing"; exit 1; }
docker exec posthog-db-1 pg_isready -q 2>/dev/null || { echo "Postgres is not up. Start the stack first (hogli start), then rerun."; exit 1; }
[ "$(curl -s --max-time 5 localhost:8010/_health)" != "Migrations are not up to date" ] || { echo "Migrations still running (localhost:8010/_health). Rerun when the backend is healthy."; exit 1; }

flox activate -- bash << 'OUTER'
set -euo pipefail
if python manage.py shell -c "from posthog.models import Team; raise SystemExit(0 if Team.objects.filter(id=1).exists() else 1)" 2>/dev/null; then
  echo "team 1 exists"
else
  python manage.py setup_dev --no-data 2>&1 | grep -v deprecated
fi
# The gateway rejects a bare wildcard for llm_gateway:read, and the gateway launcher only adds the scope to a key that already exists.
python manage.py setup_local_api_key --scopes "*" llm_gateway:read 2>&1 | grep -v "^Key:"
python manage.py shell << 'PY'
import os
from posthog.models.integration.model import Integration
from posthog.models.integration.github import GitHubIntegration
iid = os.environ["INSTALLATION_ID"]
row = Integration.objects.filter(team_id=1, kind="github", integration_id=iid).first()
if row:
    print(f"github app already seeded: integration {row.id} for installation {iid}")
else:
    row = GitHubIntegration.integration_from_installation_id(iid, team_id=1)
    print(f"github app seeded: integration {row.id} for installation {iid} ({(row.config.get('account') or {}).get('name')})")
PY
OUTER
