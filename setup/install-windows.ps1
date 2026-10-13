# Installs the CLI tools for the training into $env:USERPROFILE\bin (Windows, amd64).
# Tools already on your PATH are left alone, whatever their version; missing
# tools are installed at the versions pinned in config.env (az CLI via winget, unpinned).
# Podman is checked, not installed.
#   powershell -ExecutionPolicy Bypass -File .\setup\install-windows.ps1
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar

$config = @{}
Get-Content (Join-Path $PSScriptRoot 'config.env') |
    Where-Object { $_ -match '^\s*[A-Z_]+=' } |
    ForEach-Object { $k, $v = $_ -split '=', 2; $config[$k.Trim()] = $v.Trim() }

$binDir = if ($env:BIN_DIR) { $env:BIN_DIR } else { Join-Path $env:USERPROFILE 'bin' }
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("k8s-training-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Info($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "!!  $msg" -ForegroundColor Yellow }

function Get-File($url, $out) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out }
function Get-Text($url) { (Invoke-WebRequest -UseBasicParsing -Uri $url).Content.ToString() }

function Assert-Sha256($file, $expected) {
    $actual = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLower()
    if ($actual -ne $expected.Trim().ToLower()) {
        throw "Checksum mismatch for ${file}: expected $expected, got $actual"
    }
}

try {
    # Skips tools that are already on PATH; otherwise runs the installer block.
    function Install-IfMissing($tool, [scriptblock]$install) {
        $existing = Get-Command $tool -ErrorAction SilentlyContinue
        if ($existing) { Info "$tool already installed ($($existing.Source)), keeping it" }
        else { & $install }
    }

    Install-IfMissing kind {
        Info "kind $($config.KIND_VERSION)"
        $url = "https://github.com/kubernetes-sigs/kind/releases/download/$($config.KIND_VERSION)/kind-windows-amd64"
        Get-File $url "$tmp\kind.exe"
        Assert-Sha256 "$tmp\kind.exe" ((Get-Text "$url.sha256sum") -split '\s+')[0]
        Copy-Item "$tmp\kind.exe" "$binDir\kind.exe" -Force
    }

    Install-IfMissing kubectl {
        Info "kubectl $($config.KUBECTL_VERSION)"
        $url = "https://dl.k8s.io/release/$($config.KUBECTL_VERSION)/bin/windows/amd64/kubectl.exe"
        Get-File $url "$tmp\kubectl.exe"
        Assert-Sha256 "$tmp\kubectl.exe" (Get-Text "$url.sha256")
        Copy-Item "$tmp\kubectl.exe" "$binDir\kubectl.exe" -Force
    }

    # kubelogin: no published .sha256 for the Windows zip; relies on HTTPS
    Install-IfMissing kubelogin {
        Info "kubelogin $($config.KUBELOGIN_VERSION)"
        $url = "https://github.com/Azure/kubelogin/releases/download/$($config.KUBELOGIN_VERSION)/kubelogin-win-amd64.zip"
        Get-File $url "$tmp\kubelogin.zip"
        Expand-Archive "$tmp\kubelogin.zip" "$tmp\kubelogin" -Force
        Copy-Item "$tmp\kubelogin\bin\windows_amd64\kubelogin.exe" "$binDir\kubelogin.exe" -Force
    }

    Install-IfMissing flux {
        Info "flux $($config.FLUX_VERSION)"
        $file = "flux_$($config.FLUX_VERSION)_windows_amd64.zip"
        $base = "https://github.com/fluxcd/flux2/releases/download/v$($config.FLUX_VERSION)"
        Get-File "$base/$file" "$tmp\$file"
        $sum = (Get-Text "$base/flux_$($config.FLUX_VERSION)_checksums.txt") -split "`n" |
            Where-Object { $_ -match "\s$([regex]::Escape($file))$" } | ForEach-Object { ($_ -split '\s+')[0] }
        Assert-Sha256 "$tmp\$file" $sum
        Expand-Archive "$tmp\$file" "$tmp\flux" -Force
        Copy-Item "$tmp\flux\flux.exe" "$binDir\flux.exe" -Force
    }

    # hey (optional load generator for Lab 4)
    if (-not (Get-Command hey -ErrorAction SilentlyContinue)) {
        Info "hey"
        Get-File "https://hey-release.s3.us-east-2.amazonaws.com/hey_windows_amd64" "$binDir\hey.exe"
    }

    # az CLI
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Info "Azure CLI (winget)"
            winget install --exact --id Microsoft.AzureCLI --accept-package-agreements --accept-source-agreements
        } else {
            Warn "az CLI not found. Install: https://learn.microsoft.com/cli/azure/install-azure-cli-windows"
        }
    }

    # Podman: check only
    if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
        Warn "podman not found. Enable WSL2 (wsl --install), install Podman or Podman Desktop,"
        Warn "and create a machine with at least 4 GB memory (see setup\README.md)."
    }

    # PATH (user scope)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', "$binDir;$userPath", 'User')
        Warn "Added $binDir to your user PATH. Open a NEW terminal before continuing."
    }

    Info "Done. Next: .\setup\verify.ps1"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
