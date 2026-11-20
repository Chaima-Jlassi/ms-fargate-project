# End-to-end smoke test of the login -> order -> notification flow (Windows PowerShell).
#
#   .\scripts\smoke-test.ps1                      local docker compose (ports 3001-3003)
#   .\scripts\smoke-test.ps1 http://<alb-dns>     deployed stack, everything through the ALB
param([string]$BaseUrl = "")

if ($BaseUrl) {
    $BaseUrl = $BaseUrl.TrimEnd("/")
    $auth = $BaseUrl; $orders = $BaseUrl; $notif = $BaseUrl
} else {
    $auth = "http://localhost:3001"; $orders = "http://localhost:3002"; $notif = "http://localhost:3003"
}

$script:failed = $false

function Invoke-Call {
    param([string]$Method, [string]$Uri, [string]$Body = "", [string]$Token = "")
    $headers = @{}
    if ($Token) { $headers["Authorization"] = "Bearer $Token" }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 10 }
    if ($Body) { $params["Body"] = $Body; $params["ContentType"] = "application/json" }
    try {
        $r = Invoke-WebRequest @params
        return @{ Status = [int]$r.StatusCode; Content = $r.Content }
    } catch {
        if ($_.Exception.Response) { return @{ Status = [int]$_.Exception.Response.StatusCode; Content = "" } }
        return @{ Status = 0; Content = "" }
    }
}

function Test-Status {
    param([string]$Description, [int]$Expected, [int]$Actual)
    if ($Expected -eq $Actual) { Write-Host "PASS  $Description" }
    else { Write-Host "FAIL  $Description (expected $Expected, got $Actual)"; $script:failed = $true }
}

Write-Host "Waiting for the services to answer..."
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    $r = Invoke-Call -Method Post -Uri "$auth/auth/login" -Body '{"username":"x","password":"x"}'
    if ($r.Status -eq 401) { $ready = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $ready) { Write-Host "FAIL  services did not become ready in time"; exit 1 }

$r = Invoke-Call -Method Post -Uri "$auth/auth/login" -Body '{"username":"alice","password":"wrong"}'
Test-Status "login with a wrong password is rejected" 401 $r.Status

$r = Invoke-Call -Method Post -Uri "$auth/auth/login" -Body '{"username":"alice","password":"password123"}'
$token = ""
if ($r.Status -eq 200) { $token = ($r.Content | ConvertFrom-Json).token }
if ($token) { Write-Host "PASS  login returns a token" } else { Write-Host "FAIL  login returned no token"; exit 1 }

$item = "smoke-" + [int][double]::Parse((Get-Date -UFormat %s))
$body = "{`"item`":`"$item`",`"quantity`":2}"

$r = Invoke-Call -Method Post -Uri "$orders/orders" -Body $body
Test-Status "order without a token is rejected" 401 $r.Status
$r = Invoke-Call -Method Post -Uri "$orders/orders" -Body $body -Token "not-a-token"
Test-Status "order with an invalid token is rejected" 401 $r.Status
$r = Invoke-Call -Method Post -Uri "$orders/orders" -Body $body -Token $token
Test-Status "order with a valid token is created" 201 $r.Status
$r = Invoke-Call -Method Post -Uri "$orders/orders" -Body '{"item":"x","quantity":0}' -Token $token
Test-Status "invalid order is rejected" 400 $r.Status

$found = $false
for ($i = 0; $i -lt 10; $i++) {
    $r = Invoke-Call -Method Get -Uri "$notif/notifications"
    if ($r.Content -like "*$item*") { $found = $true; break }
    Start-Sleep -Seconds 1
}
if ($found) { Write-Host "PASS  orders triggered a notification" } else { Write-Host "FAIL  no notification found for $item"; $script:failed = $true }

Write-Host ""
if ($script:failed) { Write-Host "Some checks FAILED."; exit 1 } else { Write-Host "All checks passed."; exit 0 }
