#!/usr/bin/env bash
# hermes-verify-demoEJB-Stateless: ad-hoc verification (no test suite exists in this project).
# Rebuilds the WAR, hot-redeploys it, and asserts real container behaviour.
set -uo pipefail

PROJ="D:/APPS_EJB_20261119/demoEJB_Stateless"
MVN="/d/APPS_EJB_20261119/tools/mvn.sh"
DEPLOY="D:/Download/jboss-eap-8.0.0/jboss-eap-8.0/standalone/deployments"
LOG="D:/Download/jboss-eap-8.0.0/jboss-eap-8.0/standalone/log/server.log"
BASE="http://localhost:8080/demoEJB-Stateless"
PASS=0; FAIL=0
ok(){ echo "  PASS  $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL  $1  <<< $2"; FAIL=$((FAIL+1)); }
check(){ [ "$2" = "$3" ] && ok "$1 ($2)" || no "$1" "expected [$3] got [$2]"; }

echo "== 1. clean build =="
cd "$PROJ" || exit 1
BUILD=$("$MVN" -B -ntp clean package 2>&1)
echo "$BUILD" | grep -q "BUILD SUCCESS" && ok "mvn clean package" || no "mvn clean package" "$(echo "$BUILD" | tail -3)"
[ -f target/demoEJB-Stateless.war ] && ok "WAR produced ($(stat -c%s target/demoEJB-Stateless.war) bytes)" \
                                   || no "WAR produced" "missing"

echo "== 2. WAR content =="
LIST=$(unzip -l target/demoEJB-Stateless.war | awk '{print $4}')
for c in WEB-INF/classes/com/example/service/TaxCalculatorBean.class \
         WEB-INF/classes/com/example/web/CheckoutResource.class \
         WEB-INF/classes/com/example/web/RestApplication.class \
         WEB-INF/beans.xml index.html; do
  echo "$LIST" | grep -qx "$c" && ok "WAR has $c" || no "WAR has $c" "absent"
done
# API must be 'provided', never bundled
echo "$LIST" | grep -qi "jakarta.ejb" && no "API not bundled" "jakarta jar inside WAR" \
                                     || ok "EE API not bundled (scope=provided)"

echo "== 3. redeploy =="
MARK="$DEPLOY/demoEJB-Stateless.war.deployed"
REF=$(mktemp); sleep 1                    # reference point: marker must be NEWER than this
cp target/demoEJB-Stateless.war "$DEPLOY/" && ok "WAR copied to deployments" || no "WAR copied" "cp failed"
for i in $(seq 1 60); do
  if [ -f "$MARK" ] && [ "$MARK" -nt "$REF" ]; then FRESH=1; break; fi
  [ -f "$DEPLOY/demoEJB-Stateless.war.failed" ] && { no "deployment" "failed marker present"; break; }
  FRESH=0; sleep 1
done
rm -f "$REF"
check "fresh .deployed marker written for THIS deploy" "${FRESH:-0}" "1"
# The marker appears BEFORE the web context is re-registered; in that ~1s gap
# Undertow answers 200 with an EMPTY body — status alone is not a readiness signal.
# Require 3 consecutive real responses to be sure the redeploy cycle has finished.
for i in $(seq 1 40); do
  GOOD=0
  for k in 1 2 3; do
    printf '%s' "$(curl -s "$BASE/api/checkout?price=1")" | grep -q servedByBeanInstance \
      && GOOD=$((GOOD+1)) || break
    sleep 0.4
  done
  [ "$GOOD" -eq 3 ] && { READY=1; break; }
  READY=0; sleep 1
done
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/checkout?price=1")
check "endpoint reachable after redeploy" "$CODE" "200"
check "endpoint returns stable real content (not the post-redeploy empty window)" "${READY:-0}" "1"

echo "== 4. maths / binding behaviour =="
q(){ curl -sS --retry 2 --max-time 10 -H 'Connection: close' "$BASE/api/checkout$1"; }
# assert via python: total == price*(1+rate), tax == total-price, keys present, instance id non-empty
assert_json(){ # $1=label $2=query $3=price $4=rate
  local body; body=$(q "$2")
  local res; res=$(printf '%s' "$body" | python -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception as e:
    print("PARSE_ERR", e); raise SystemExit
want_p, want_r = float(sys.argv[1]), float(sys.argv[2])
exp = want_p * (1 + want_r)
bad = []
if abs(d.get("price", -1) - want_p) > 1e-9: bad.append("price")
if abs(d.get("taxRate", -1) - want_r) > 1e-9: bad.append("taxRate")
if abs(d.get("total", -1) - exp) > 1e-9: bad.append("total=%s want %s" % (d.get("total"), exp))
if abs(d.get("tax", -1) - (exp - want_p)) > 1e-9: bad.append("tax")
if not d.get("servedByBeanInstance"): bad.append("servedByBeanInstance missing")
print("OK" if not bad else "BAD:" + ",".join(bad))
' "$3" "$4")
  check "$1" "$res" "OK"
}
assert_json "price=100 rate=0.08 -> 108.0"        "?price=100&rate=0.08" 100 0.08
assert_json "price=250 rate=0.20 -> 300.0"        "?price=250&rate=0.20" 250 0.20
assert_json "defaults (price=100 rate=0.08)"      ""                     100 0.08
assert_json "rate=0 -> no tax"                    "?price=42&rate=0"     42  0
assert_json "decimal price 19.99 @ 0.05"          "?price=19.99&rate=0.05" 19.99 0.05

echo "== 5. pooled instance identity =="
IDS_FILE=$(mktemp); BAD=0
for i in 1 2 3 4 5; do
  body=$(q "?price=10")
  id=$(printf '%s' "$body" | python -c 'import sys,json
try: print(json.load(sys.stdin).get("servedByBeanInstance") or "")
except Exception: print("")' 2>/dev/null)
  if [ -n "$id" ]; then echo "$id" >> "$IDS_FILE"
  else BAD=$((BAD+1)); echo "  info  call $i unparseable: [$body]"; fi
done
check "all 5 calls returned a bean instance id" "$BAD" "0"
N=$(sort -u "$IDS_FILE" | wc -l | tr -d ' ')
[ "$N" -ge 1 ] && ok "5 calls served by $N distinct pooled instance(s)" || no "pool identity" "none found"
rm -f "$IDS_FILE"

echo "== 6. landing page =="
PAGE=$(curl -s "$BASE/")
echo "$PAGE" | grep -q "@Stateless" && ok "index.html served with expected content" \
                                    || no "index.html content" "marker text missing"
echo "  info  page length: ${#PAGE} chars"

echo "== 7. container log evidence =="
grep -aq "JNDI bindings for session bean named 'TaxCalculatorBean'" "$LOG" \
  && ok "container registered the EJB (WFLYEJB0473 JNDI bindings)" \
  || no "JNDI binding line" "not in server.log"
grep -aq "\[TaxCalculatorBean\] @PostConstruct" "$LOG" \
  && ok "@PostConstruct callback fired" || no "@PostConstruct" "no log line"
grep -aq "calculateTotalWithTax" "$LOG" \
  && ok "business method invoked through proxy" || no "business method log" "no log line"
grep -aq 'Deployed "demoEJB-Stateless.war"' "$LOG" \
  && ok "server logged successful deployment" || no "deployment log" "no log line"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
