# REV-71 §6 matrix driver — KJDEV only. Orchestrates 22 scenarios:
#   build (apex) -> calc+save per quote (apex, QLE-equivalent) -> wait for async
#   calculator -> optional mutation -> re-calc -> verify via SOQL -> results table.
# Writes audit-reports/rev71-matrix-results.md. Read-only against everything
# except the ZZ REV71-M* records it creates.
$ErrorActionPreference = 'Stop'
$env:HTTP_PROXY = $null; $env:HTTPS_PROXY = $null
$proj = 'C:\sf-work\kjdev'
$tmp  = Join-Path $env:TEMP 'rev71_matrix'
New-Item -ItemType Directory -Force $tmp | Out-Null
$results = @()

function Invoke-Apex([string]$templateFile, [int]$n, [int]$qidx = 0) {
    $src = Get-Content (Join-Path $proj "scripts\$templateFile") -Raw
    $src = $src.Replace('__N__', $n).Replace('__QIDX__', $qidx)
    $f = Join-Path $tmp "run_$($templateFile)_$($n)_$($qidx).apex"
    Set-Content -Path $f -Value $src -Encoding utf8
    $out = sf apex run -f $f -o KJDEV --json 2>$null | Out-String
    if ($out -notmatch '"success":\s*true') {
        $m = [regex]::Match($out, '(FATAL_ERROR|exceptionMessage"\s*:\s*")[^\\"]{0,300}')
        throw "Apex failed [$templateFile N=$n]: $($m.Value)"
    }
    return $out
}

function Wait-CalcDone {
    # poll until no CPQ calculator queueables remain in flight (max ~90s)
    for ($i = 0; $i -lt 18; $i++) {
        $q = sf data query -o KJDEV --json -q "SELECT COUNT(Id) c FROM AsyncApexJob WHERE ApexClass.Name = 'QueueableCalculatorService' AND Status IN ('Queued','Processing','Preparing','Holding')" | Out-String
        $j = ($q.Substring($q.IndexOf('{')) | ConvertFrom-Json)
        if ($j.result.records[0].c -eq 0) { return }
        Start-Sleep -Seconds 5
    }
    Write-Warning 'Calculator queueables still in flight after 90s — continuing'
}

function Get-Lines([int]$n) {
    $tag = 'ZZ REV71-M' + $n.ToString('00')
    $ql = sf data query -o KJDEV --json -q "SELECT SBQQ__Product__r.ProductCode pc, Full_Contract_Value__c v, SBQQ__RequiredBy__c rb FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Opportunity2__r.Name = '$tag' ORDER BY SBQQ__Number__c" | Out-String
    $ol = sf data query -o KJDEV --json -q "SELECT PricebookEntry.Product2.ProductCode pc, Full_Contract_Value__c v, SBQQ__ParentID__c pid FROM OpportunityLineItem WHERE Opportunity.Name = '$tag'" | Out-String
    $jq = ($ql.Substring($ql.IndexOf('{')) | ConvertFrom-Json).result.records
    $jo = ($ol.Substring($ol.IndexOf('{')) | ConvertFrom-Json).result.records
    $qlS = ($jq | ForEach-Object { $code = $_.SBQQ__Product__r.ProductCode; $child = ''; if ($_.SBQQ__RequiredBy__c) { $child = '(child)' }; "$code$child=$($_.Full_Contract_Value__c)" }) -join ' '
    $olS = ($jo | ForEach-Object { $code = $_.PricebookEntry.Product2.ProductCode; $child = ''; if ($_.SBQQ__ParentID__c) { $child = '(child)' }; "$code$child=$($_.Full_Contract_Value__c)" }) -join ' '
    return @{ QL = $qlS; OLI = $olS; QLrec = $jq; OLrec = $jo }
}

function Get-NoAnchorLogCount {
    $q = sf data query -o KJDEV --json -q "SELECT COUNT(Id) c FROM Flow_Log__c WHERE Class_Name__c LIKE '%no anchor%' AND CreatedDate = TODAY" | Out-String
    return ($q.Substring($q.IndexOf('{')) | ConvertFrom-Json).result.records[0].c
}

# expected-value evaluators: standalone lines must equal $code, children must stay null
function Test-Standalone($recs, $code, $isQL) {
    foreach ($r in $recs) {
        if ($isQL) { $isChild = [bool]$r.SBQQ__RequiredBy__c } else { $isChild = [bool]$r.SBQQ__ParentID__c }
        $v = $r.Full_Contract_Value__c
        if ($isChild) { if ($null -ne $v) { return $false } }
        else {
            if ($null -eq $code) { if ($null -ne $v) { return $false } }
            elseif ($v -ne $code) { return $false }
        }
    }
    return $true
}

$plan = @(
    @{ N=1;  Expect=$null; HasOli=$true;  Note='single product - field untouched' }
    @{ N=2;  Expect=$null; HasOli=$true;  Note='lone bundle - untouched' }
    @{ N=3;  Expect=1;     HasOli=$true;  Note='LAWM+LNVM -> 1' }
    @{ N=4;  Expect=1;     HasOli=$true;  Note='2-year, 4 lines -> all 1' }
    @{ N=5;  Expect=2;     HasOli=$true;  Note='GLBM+LAWM -> 2 (GLL decisive)' }
    @{ N=6;  Expect=2;     HasOli=$true;  Note='GLBM+LWKM -> 2' }
    @{ N=7;  Expect=1;     HasOli=$true;  Note='LAWM pricier -> 1 (VAR)' }
    @{ N=8;  Expect=3;     HasOli=$true;  Note='LWKM pricier -> 3 (VAR)' }
    @{ N=9;  Expect=3;     HasOli=$true;  Note='LWKM+TALM -> 3' }
    @{ N=10; Expect=1;     HasOli=$true;  Mutate=$true; Note='line added -> all re-stamped 1' }
    @{ N=11; Expect=$null; HasOli=$true;  Mutate=$true; Note='line deleted -> code cleared' }
    @{ N=12; Expect=3;     HasOli=$true;  Mutate=$true; Note='repriced -> flips 1 to 3' }
    @{ N=13; Expect=$null; HasOli=$true;  LogDelta=$true; Note='no anchor -> no code + log' }
    @{ N=14; Expect=$null; HasOli=$true;  LogDelta=$true; Note='bundle+standalone, no anchor (Q4)' }
    @{ N=15; Expect=1;     HasOli=$false; Bulk=$true; Note='200 lines / 10 quotes -> all 1' }
    @{ N=16; Expect=1;     HasOli=$true;  MutateOnly=$true; Note='legacy children untouched, standalone 1' }
    @{ N=17; Expect=1;     HasOli=$true;  Note='QLE-equivalent add+save' }
    @{ N=18; Expect=1;     HasOli=$true;  Mutate=$true; Note='primary after stamp -> OLIs born coded' }
    @{ N=19; Expect=1;     HasOli=$true;  Note='renewal-type quote (approx)' }
    @{ N=20; Expect=3;     HasOli=$true;  Note='amendment-type quote (approx)' }
    @{ N=21; Expect=1;     HasOli=$true;  NoQuote=$true; Note='manual OLIs -> Layer 2 stamps' }
    @{ N=22; Expect=1;     HasOli=$true;  NoQuote=$true; MutateOnly=$true; Note='same-value touch -> no churn' }
)

foreach ($s in $plan) {
    $n = $s.N
    Write-Host ">>> Scenario $n — $($s.Note)"
    $logBefore = 0
    if ($s.LogDelta) { $logBefore = Get-NoAnchorLogCount }
    try {
        Invoke-Apex 'rev71_matrix_builder.apex' $n | Out-Null
        if (-not $s.NoQuote -and $n -ne 16) {
            $qCount = 1; if ($s.Bulk) { $qCount = 10 }
            for ($qi = 0; $qi -lt $qCount; $qi++) { Invoke-Apex 'rev71_matrix_calc.apex' $n $qi | Out-Null }
            Wait-CalcDone
        }
        if ($s.Mutate -or $s.MutateOnly) {
            Invoke-Apex 'rev71_matrix_mutate.apex' $n | Out-Null
            if ($s.Mutate -and -not ($n -eq 18)) {  # 18's mutation IS the primary flip; no recalc
                Invoke-Apex 'rev71_matrix_calc.apex' $n 0 | Out-Null
            }
            Wait-CalcDone
        }
        $lines = Get-Lines $n
        $passQL = $true
        if (-not $s.NoQuote -and $n -ne 16) { $passQL = Test-Standalone $lines.QLrec $s.Expect $true }
        $passOLI = $true
        if ($s.HasOli) { $passOLI = Test-Standalone $lines.OLrec $s.Expect $false }
        $passLog = $true
        if ($s.LogDelta) { $passLog = ((Get-NoAnchorLogCount) - $logBefore) -ge 1 }
        $verdict = 'PASS'; if (-not ($passQL -and $passOLI -and $passLog)) { $verdict = 'FAIL' }
        $results += [PSCustomObject]@{ N=$n; Result=$verdict; QL=$lines.QL; OLI=$lines.OLI; Note=$s.Note }
        Write-Host "    $verdict  QL[$($lines.QL)] OLI[$($lines.OLI)]"
    } catch {
        $results += [PSCustomObject]@{ N=$n; Result='ERROR'; QL=''; OLI=''; Note=$_.Exception.Message }
        Write-Host "    ERROR $($_.Exception.Message)"
    }
}

$md = "# REV-71 §6 Matrix Results — KJDEV, $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n`n"
$md += "| # | Result | Quote lines | OLIs | Scenario |`n|---|---|---|---|---|`n"
foreach ($r in $results) { $md += "| $($r.N) | $($r.Result) | $($r.QL) | $($r.OLI) | $($r.Note) |`n" }
$out = Join-Path $proj 'audit-reports\rev71-matrix-results.md'
Set-Content -Path $out -Value $md -Encoding utf8
Write-Host "`nResults written to $out"
$results | Format-Table N, Result, Note -AutoSize
