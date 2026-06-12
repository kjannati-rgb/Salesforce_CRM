#!/usr/bin/env bash
# REV-71 S6 matrix driver (bash port - Windows Defender AMSI false-positived the .ps1).
# Same orchestration: build -> calc per quote -> wait for async calculator ->
# mutate -> recalc -> verify -> markdown results table. KJDEV only; touches only
# ZZ REV71-M* records it creates.
set -u
PROJ="/c/sf-work/kjdev"
TMP="$(mktemp -d)"
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
OUTMD="$PROJ/audit-reports/rev71-matrix-results.md"
ROWS=""

run_apex() { # template-file N QIDX
  local tpl="$1" n="$2" qidx="${3:-0}" f out
  f="$TMP/run_${tpl}_${n}_${qidx}.apex"
  sed -e "s/__N__/$n/g" -e "s/__QIDX__/$qidx/g" "$PROJ/scripts/$tpl" > "$f"
  out=$(sf apex run -f "$f" -o KJDEV --json 2>&1)
  if ! grep -q '"success": *true' <<<"$out"; then
    grep -o 'FATAL_ERROR[^"\\]\{0,200\}' <<<"$out" | head -2 >&2
    return 1
  fi
  return 0
}

wait_calc() {
  local i c
  for i in $(seq 1 18); do
    # JSON + grep: CSV mode renders aggregate COUNT values as an empty row (CLI quirk)
    c=$(sf data query -o KJDEV --json -q "SELECT COUNT(Id) c FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableCalculatorService' AND Status IN ('Queued','Processing','Preparing','Holding')" 2>/dev/null | grep -o '"c": *[0-9]*' | grep -o '[0-9]*$')
    [ "$c" = "0" ] && return 0
    sleep 5
  done
  echo "WARN: calculator still busy after 90s" >&2
}

noanchor_count() {
  sf data query -o KJDEV --json -q "SELECT COUNT(Id) c FROM Flow_Log__c WHERE Class_Name__c LIKE '%no anchor%' AND CreatedDate = TODAY" 2>/dev/null | grep -o '"c": *[0-9]*' | grep -o '[0-9]*$'
}

# check_csv <csv-text> <expect>  : col1=code col2=value col3=childmarker
# standalone rows must equal expect ("" = null); child rows must stay empty.
check_csv() {
  local csv="$1" expect="$2" line code val marker ok=1 first=1
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [ $first -eq 1 ] && { first=0; continue; }   # header
    [ -z "$line" ] && continue
    code=$(cut -d',' -f1 <<<"$line" | tr -d '"')
    val=$(cut -d',' -f2 <<<"$line" | tr -d '"')
    marker=$(cut -d',' -f3- <<<"$line" | tr -d '",')
    val="${val%.0}"
    if [ -n "$marker" ]; then
      [ -n "$val" ] && ok=0   # child line must stay untouched
    else
      if [ -z "$expect" ]; then [ -n "$val" ] && ok=0
      else [ "$val" = "$expect" ] || ok=0; fi
    fi
  done <<<"$csv"
  echo $ok
}

fmt_csv() { # compact "CODE=val CODE(child)=val" summary for the report
  local csv="$1" line code val marker out="" first=1
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [ $first -eq 1 ] && { first=0; continue; }
    [ -z "$line" ] && continue
    code=$(cut -d',' -f1 <<<"$line" | tr -d '"')
    val=$(cut -d',' -f2 <<<"$line" | tr -d '"'); val="${val%.0}"
    marker=$(cut -d',' -f3- <<<"$line" | tr -d '",')
    if [ -n "$marker" ]; then out="$out ${code}(child)=${val}"; else out="$out ${code}=${val}"; fi
  done <<<"$csv"
  echo "${out# }"
}

# plan: N|expect|flags|note   (flags: quote,oli,bulk,mutate,mutateonly,logdelta)
PLAN="
1||quote,oli|single product - field untouched
2||quote,oli|lone bundle - untouched
3|1|quote,oli|LAWM+LNVM -> 1
4|1|quote,oli|2-year 4 lines -> all 1
5|2|quote,oli|GLBM+LAWM -> 2 (GLL decisive)
6|2|quote,oli|GLBM+LWKM -> 2
7|1|quote,oli|LAWM pricier -> 1 (VAR)
8|3|quote,oli|LWKM pricier -> 3 (VAR)
9|3|quote,oli|LWKM+TALM -> 3
10|1|quote,oli,mutate|line added -> all re-stamped 1
11||quote,oli,mutate|line deleted -> code cleared
12|3|quote,oli,mutate|repriced -> flips 1 to 3
13||quote,oli,logdelta|no anchor -> no code + log
14||quote,oli,logdelta|bundle+standalone no anchor (Q4)
15|1|quote,bulk|200 lines / 10 quotes -> all 1
16|1|oli,mutateonly|legacy children untouched standalone 1
17|1|quote,oli|QLE-equivalent add+save
18|1|quote,oli,mutate|primary after stamp -> OLIs born coded
19|1|quote,oli|renewal-type quote (approx)
20|3|quote,oli|amendment-type quote (approx)
21|1|oli|manual OLIs -> Layer 2 stamps
22|1|oli,mutateonly|same-value touch -> no churn
"

while IFS='|' read -r -u 3 N EXPECT FLAGS NOTE; do
  [ -z "${N// }" ] && continue
  TAG=$(printf 'ZZ REV71-M%02d' "$N")
  has() { [[ ",$FLAGS," == *",$1,"* ]]; }
  echo ">>> Scenario $N - $NOTE"
  LOGBEFORE=0; has logdelta && LOGBEFORE=$(noanchor_count)
  VERDICT="PASS"; QLS=""; OLS=""
  if ! run_apex rev71_matrix_builder.apex "$N"; then
    VERDICT="ERROR(build)"
  else
    if has quote; then
      QC=1; has bulk && QC=10
      qi=0
      while [ $qi -lt $QC ]; do
        run_apex rev71_matrix_calc.apex "$N" "$qi" || VERDICT="ERROR(calc$qi)"
        qi=$((qi+1))
      done
      wait_calc
    fi
    if [[ "$VERDICT" == PASS ]] && { has mutate || has mutateonly; }; then
      run_apex rev71_matrix_mutate.apex "$N" || VERDICT="ERROR(mutate)"
      if [[ "$VERDICT" == PASS ]] && has mutate && [ "$N" != "18" ]; then
        run_apex rev71_matrix_calc.apex "$N" 0 || VERDICT="ERROR(recalc)"
      fi
      wait_calc
    fi
    if [[ "$VERDICT" == PASS ]]; then
      QLCSV=$(sf data query -o KJDEV -r csv -q "SELECT SBQQ__Product__r.ProductCode, Full_Contract_Value__c, SBQQ__RequiredBy__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Opportunity2__r.Name = '$TAG' ORDER BY SBQQ__Number__c" 2>/dev/null)
      OLCSV=$(sf data query -o KJDEV -r csv -q "SELECT PricebookEntry.Product2.ProductCode, Full_Contract_Value__c, SBQQ__ParentID__c FROM OpportunityLineItem WHERE Opportunity.Name = '$TAG'" 2>/dev/null)
      QLS=$(fmt_csv "$QLCSV"); OLS=$(fmt_csv "$OLCSV")
      PASSQL=1; has quote && PASSQL=$(check_csv "$QLCSV" "$EXPECT")
      PASSOL=1; has oli && PASSOL=$(check_csv "$OLCSV" "$EXPECT")
      PASSLOG=1
      if has logdelta; then
        AFTER=$(noanchor_count)
        [ $(( ${AFTER:-0} - ${LOGBEFORE:-0} )) -ge 1 ] || PASSLOG=0
      fi
      if [ "$PASSQL" != "1" ] || [ "$PASSOL" != "1" ] || [ "$PASSLOG" != "1" ]; then VERDICT="FAIL"; fi
    fi
  fi
  echo "    $VERDICT  QL[$QLS] OLI[$OLS]"
  ROWS="$ROWS| $N | $VERDICT | $QLS | $OLS | $NOTE |
"
done 3<<<"$PLAN"

{
  echo "# REV-71 S6 Matrix Results - KJDEV, $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "| # | Result | Quote lines | OLIs | Scenario |"
  echo "|---|---|---|---|---|"
  printf '%s' "$ROWS"
} > "$OUTMD"
echo
echo "Results written to $OUTMD"
