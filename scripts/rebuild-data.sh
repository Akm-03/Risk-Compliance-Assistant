#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PSQL="docker compose exec -T db psql -U aria -d aria -v ON_ERROR_STOP=1"
test -f data/HI-Small_Trans.csv || { echo "put HI-Small_Trans.csv in ~/aria/data/"; exit 1; }

echo "1/4 loading raw CSV...";    $PSQL -c "TRUNCATE eval.raw_tx RESTART IDENTITY"
$PSQL -c "\copy eval.raw_tx(ts,from_bank,from_acct,to_bank,to_acct,amt_received,cur_received,amt_paid,cur_paid,pay_format,is_laundering) FROM STDIN WITH (FORMAT csv, HEADER true)" < data/HI-Small_Trans.csv
echo "2/4 building the window...";  $PSQL < backend/db/load_window.sql
echo "3/4 seeding customers...";    $PSQL < backend/db/seed_02.sql
echo "4/4 subject references...";   (cd backend && node scripts/fill-subject-refs.js)
echo "done"