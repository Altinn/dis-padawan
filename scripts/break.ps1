# Breaks your podinfo on purpose. Your job: find out what's wrong with
# kubectl get / describe / events / logs [--previous] / exec, then fix it.
#
#   .\scripts\break.ps1 kind              # random scenario on your kind cluster
#   .\scripts\break.ps1 kind 3            # a specific scenario
#   .\scripts\break.ps1 aks <name>        # random scenario on AKS (suspends your Flux Kustomization)
#   .\scripts\break.ps1 aks <name> 6
#   .\scripts\break.ps1 hint <number>     # a nudge, if you're stuck
#
# Fix on kind: kubectl apply -k participants/<name>/overlays/kind
# Fix on AKS:  flux resume kustomization <name> -n product-dis-padawan
#              (Flux re-applies what's in git; that's the GitOps way to undo a manual change)
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$config = @{}
Get-Content (Join-Path $PSScriptRoot '..\setup\config.env') |
    Where-Object { $_ -match '^\s*[A-Z_]+=' } |
    ForEach-Object { $k, $v = $_ -split '=', 2; $config[$k.Trim()] = $v.Trim() }

$ns = $config.TRAINING_NAMESPACE
$kindScenarios = 1..5
$aksScenarios = 1..7

function Show-Usage {
    Get-Content $PSCommandPath | Select-Object -Skip 1 -First 12 | ForEach-Object { $_ -replace '^# ?', '' }
    exit 1
}

function Show-Hint($n) {
    switch ($n) {
        1 { "Look at the pod's events: kubectl describe pod. What is it waiting for?" }
        2 { "The container starts and stops. What did it say before it died? kubectl logs --previous" }
        3 { "Pods are Running but not Ready. Which check decides Ready, and what does it call?" }
        4 { "Check 'Last State' and 'Reason' in kubectl describe pod. Compare with the container's limits." }
        5 { "The pods look fine. Does the Service find them? kubectl get endpointslices; compare labels." }
        6 { "Pods can't start their container. Follow the chain: ExternalSecret status -> Secret -> pod events." }
        7 { "Pods and Service are fine. Is the route attached to the gateway? kubectl describe httproute" }
        default { Write-Error "No such scenario" }
    }
}

# Uses a patch file (UTF-8 without BOM): no PowerShell quoting surprises with JSON.
function Invoke-Patch($target, $type, $json) {
    $f = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($f, $json)
    kubectl --context $script:ctx -n $ns patch $target --type $type --patch-file $f | Out-Null
    $code = $LASTEXITCODE
    Remove-Item $f -Force
    if ($code -ne 0) { throw "kubectl patch $target failed" }
}

if ($args.Count -lt 1) { Show-Usage }
switch ($args[0]) {
    'hint' { if ($args.Count -ne 2) { Show-Usage }; Show-Hint ([int]$args[1]); exit 0 }
    'kind' { $script:ctx = 'kind-k8s-training'; $prefix = ''; $scenarios = $kindScenarios; $choice = $args[1] }
    'aks' {
        if ($args.Count -lt 2) { Show-Usage }
        $script:ctx = $config.AKS_CONTEXT; $prefix = "$($args[1])-"; $scenarios = $aksScenarios; $choice = $args[2]
    }
    default { Show-Usage }
}

if (-not $choice) {
    $choice = Get-Random -InputObject $scenarios
} elseif ($scenarios -notcontains [int]$choice) {
    Write-Error "Scenario $choice is not available on $($args[0]) (available: $($scenarios -join ' '))"
}
$choice = [int]$choice

$deploy = "deployment/${prefix}podinfo"
kubectl --context $ctx -n $ns get $deploy *> $null
if ($LASTEXITCODE -ne 0) { Write-Error "No $deploy in $ns on $ctx. Deploy podinfo first." }

if ($args[0] -eq 'aks') {
    # Otherwise Flux reverts the break within its 2-minute drift check.
    Invoke-Patch "kustomizations.kustomize.toolkit.fluxcd.io/$($args[1])" merge '{"spec":{"suspend":true}}'
    Write-Host "Your Flux Kustomization '$($args[1])' is suspended, so Flux won't undo the break."
}

switch ($choice) {
    1 { # ImagePullBackOff: a tag that doesn't exist
        $image = kubectl --context $ctx -n $ns get $deploy -o jsonpath='{.spec.template.spec.containers[0].image}'
        $repo = $image.Substring(0, $image.LastIndexOf(':'))
        Invoke-Patch $deploy json "[{`"op`":`"replace`",`"path`":`"/spec/template/spec/containers/0/image`",`"value`":`"${repo}:6.15.99`"}]"
    }
    2 { # CrashLoopBackOff: unknown flag, podinfo exits with code 2
        Invoke-Patch $deploy json '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--colour=red"}]'
    }
    3 { # Readiness probe on a path that doesn't exist: Running, never Ready
        Invoke-Patch $deploy json '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/ready"}]'
    }
    4 { # OOMKilled: loads 256 MB into memory with a 128Mi limit
        Invoke-Patch $deploy json '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--stress-memory=256"}]'
    }
    5 { # Service selects no pods
        Invoke-Patch "service/${prefix}podinfo" merge '{"spec":{"selector":{"app.kubernetes.io/name":"podinfo-api"}}}'
    }
    6 { # ExternalSecret reads a key that doesn't exist; Secret gone; new pods can't start
        Invoke-Patch "externalsecret/${prefix}demo-secret" json '[{"op":"replace","path":"/spec/data/0/remoteRef/key","value":"demo-apikey"}]'
        kubectl --context $ctx -n $ns delete secret "${prefix}demo-secret" --ignore-not-found | Out-Null
        kubectl --context $ctx -n $ns rollout restart $deploy | Out-Null
    }
    7 { # HTTPRoute points at a gateway listener that doesn't exist
        Invoke-Patch "httproute/${prefix}podinfo" json '[{"op":"add","path":"/spec/parentRefs/0/sectionName","value":"public"}]'
    }
}

Write-Host "Broke scenario #$choice. Something is wrong with your podinfo now. Find out what."
Write-Host "Stuck? .\scripts\break.ps1 hint $choice"
