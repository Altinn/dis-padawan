# Pre-training environment check (Windows). Run it on the network you normally use to reach AKS.
#   .\setup\verify.ps1            # all checks
#   .\setup\verify.ps1 -SkipAks   # only local checks (tools, Podman, images)
# Checks that everything is ready; it does not create anything. The kind cluster is created in Lab 1.
#Requires -Version 5.1
param([switch]$SkipAks)

$config = @{}
Get-Content (Join-Path $PSScriptRoot 'config.env') |
    Where-Object { $_ -match '^\s*[A-Z_]+=' } |
    ForEach-Object { $k, $v = $_ -split '=', 2; $config[$k.Trim()] = $v.Trim() }

$script:Failed = 0
function Ok($msg)   { Write-Host "  OK   $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:Failed++ }
function Section($msg) { Write-Host "`n$msg" -ForegroundColor White }
function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Check-Version($name, $expected, $actual) {
    if ("$actual" -like "*$expected*") { Ok "$name $expected" } else { Warn "${name}: found $actual (training tested with $expected; usually fine)" }
}

Section "Tools"
foreach ($t in 'git', 'kind', 'kubectl', 'az', 'kubelogin') {
    if (-not (Has $t)) { Fail "$t not found on PATH (run setup\install-windows.ps1, then open a new terminal)" }
}
if (Has kind)      { Check-Version kind $config.KIND_VERSION (kind version) }
if (Has kubectl)   { Check-Version kubectl $config.KUBECTL_VERSION ((kubectl version --client 2>$null) | Select-Object -First 1) }
if (Has kubelogin) { Check-Version kubelogin $config.KUBELOGIN_VERSION ((kubelogin --version 2>$null) -join ' ') }
if (Has flux)      { Check-Version flux $config.FLUX_VERSION (flux version --client 2>$null) } else { Warn "flux not found (optional)" }
if (Has hey)       { Ok "hey" } else { Warn "hey not found (optional, Lab 4)" }
if (Has az) {
    # Parse JSON instead of --query: native-arg quoting differs between PowerShell 5.1 and 7.3+.
    $azVer = (az version -o json 2>$null | ConvertFrom-Json).'azure-cli'
    if ($azVer -and ([version]$azVer -ge [version]$config.AZ_CLI_MIN_VERSION)) { Ok "az $azVer" }
    else { Fail "az '$azVer' is older than $($config.AZ_CLI_MIN_VERSION)" }
}

Section "Podman"
if (-not (Has podman)) {
    Fail "podman not found on PATH (see setup\README.md)"
} else {
    podman info *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail "podman is not running: podman machine start (WSL2 must be enabled)"
    } else {
        Ok "podman is running"
        if ((podman info --format '{{.Host.Security.Rootless}}' 2>$null) -ne 'false') {
            Fail "podman machine is rootless; kind needs rootful: podman machine stop; podman machine set --rootful; podman machine start"
        }
        # MemTotal is what the machine's kernel sees, a bit below the configured size,
        # so a 4096 MiB machine reports roughly 3.8 GiB. 3500 MiB leaves room for that.
        $memMiB = [math]::Floor([double](podman info --format '{{.Host.MemTotal}}' 2>$null) / 1MB)
        # WSL2-backed machines get their memory from WSL (.wslconfig), not from 'podman machine set --memory'.
        if ($memMiB -ge 3500) { Ok "podman machine memory $memMiB MiB" }
        else { Fail "podman machine has $memMiB MiB memory, kind needs 4 GB: set 'memory=4GB' under [wsl2] in $env:USERPROFILE\.wslconfig, then 'wsl --shutdown' and 'podman machine start'" }
    }
}
if ($env:KIND_EXPERIMENTAL_PROVIDER -ne 'podman') {
    Fail "KIND_EXPERIMENTAL_PROVIDER is not set to podman (see setup\README.md)"
}

Section "Images (pre-pulled so Lab 1 starts fast)"
# Read the pinned node image from kind-config.yaml so there is one source of truth.
$kindNodeImage = (Select-String -Path (Join-Path $PSScriptRoot 'kind-config.yaml') -Pattern '^\s*image:\s*(\S+)' |
    Select-Object -First 1).Matches[0].Groups[1].Value
foreach ($image in @($kindNodeImage, $config.PODINFO_IMAGE)) {
    podman pull -q $image *> $null
    if ($LASTEXITCODE -eq 0) { Ok "pulled $(($image -split '@')[0])" }
    else { Fail "could not pull $image (network/proxy/DNS in the Podman machine?)" }
}

if (-not $SkipAks) {
    Section "AKS and Azure"
    $user = az account show --query user.name -o tsv 2>$null
    if ($LASTEXITCODE -eq 0) { Ok "az logged in ($user)" } else { Fail "not logged in: run 'az login'" }

    kubectl config get-contexts $config.AKS_CONTEXT *> $null
    if ($LASTEXITCODE -eq 0) {
        $server = kubectl config view --minify --context $config.AKS_CONTEXT -o jsonpath='{.clusters[0].cluster.server}' 2>$null
        if ($server -like '*.privatelink.*') {
            Fail "kubeconfig uses the private FQDN ($server): re-run the az aks get-credentials command from the invitation email"
        } else {
            # Any HTTP status (even 401) proves the API server is reachable; 000 means no connection.
            # curl.exe (built into Windows 10+), not the PowerShell 5.1 'curl' alias.
            $code = curl.exe -sk -o NUL -w '%{http_code}' --max-time 10 "$server/healthz"
            if ($code -eq '000' -or -not $code) { Fail "AKS API $server not reachable (can you reach your other AKS clusters from this machine?)" }
            else { Ok "AKS API reachable ($server)" }
        }
        $can = kubectl --context $config.AKS_CONTEXT auth can-i list pods -n $config.TRAINING_NAMESPACE 2>$null
        if ($can -eq 'yes') { Ok "kubectl can list pods in $($config.TRAINING_NAMESPACE) on AKS" }
        else { Fail "no access to $($config.TRAINING_NAMESPACE) on $($config.AKS_CONTEXT) (group membership? kubelogin?)" }
    } else {
        Fail "kube context '$($config.AKS_CONTEXT)' missing: see setup\README.md 'Connect to AKS'"
    }
}

Write-Host ""
if ($script:Failed -eq 0) {
    Write-Host "All required checks passed." -ForegroundColor Green
} else {
    Write-Host "$($script:Failed) check(s) failed. Send the output above to the trainer." -ForegroundColor Red
    exit 1
}
