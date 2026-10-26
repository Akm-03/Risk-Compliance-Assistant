#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/aria-env.sh"
H=$(node -e "console.log(require('crypto').createHash('sha256').update('x').digest('hex'))")

mk() { # $1 = model version
  node -e "console.log(JSON.stringify({function:'LogComplianceEvent',Args:[JSON.stringify({
    schemaVersion:1,eventId:'evt-'+Date.now(),eventType:'AML_DECISION',subjectRef:'$H',
    decision:'ESCALATE',riskBand:'HIGH',recordHash:'$H',contextHash:'$H',
    modelVersion:'$1',promptVersion:'prompt-v1'})]}))"
}

setOrg 3
invokeAria "{\"function\":\"RegisterModel\",\"Args\":[\"kiran-v1\",\"prompt-v1\",\"$H\"]}"; sleep 3

setOrg 1
invokeAria "$(mk kiran-v1)"; sleep 3
peer chaincode query -C $CHANNEL -n $CC_NAME -c "{\"function\":\"GetEventsBySubject\",\"Args\":[\"$H\"]}"

echo "--- negative test: unregistered model must be rejected ---"
if invokeAria "$(mk rogue-v9)"; then echo "FAIL: rogue model accepted"; exit 1; else echo "OK: rejected"; fi