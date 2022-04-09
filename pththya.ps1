<#
    .SYNOPSIS
    Deploys a pre-built and configure penetration testing environment.

    .DESCRIPTION
    Deploys a pre-built and configure penetration testing environment.
    Templates are not supplied in this repo. Made for 1-10 users.

    .LINK
    Github: https://github.com/OrneLibrary/Pththya
#>

param (
    [Parameter(Mandatory=$true)][string]$json
)


$jsonConfig = Get-Content $json | ConvertFrom-Json


Import-Module .\obed.psm1

Test-PSInterpreter
Import-PowerCLI
Initialize-VCenter
$vmHost = Get-Node
$datastore = Get-NodeDatastore -vmHost $vmHost

# Password for running commands on VMs
$guestPassword = Read-Host -Prompt "Password for CPT account on Kali and Commando" -AsSecureString

# Check for correct default NIC configuration
while ($true){
    if ((Get-VirtualSwitch -name "vswitch0" -VMHost $vmHost | Select-Object -ExpandProperty Nic) -notmatch 'vmnic5') {
        Write-Host "vSwitch0 needs to be set to vmnic5 in the Virtual Switch tab for proper deployment.`nPlease make that configuration change before continuing."  -ForegroundColor Red -BackgroundColor Black
        pause
    }
    else { Break }
}



# Setting up the networking 
Write-Host "Setting up networking..."
foreach ($network in $jsonConfig.Networks) { New-Network $network $vmhost}


# Allowing autostart of VMs
Get-VMHostStartPolicy -VMHost $vmHost | Set-VMHostStartPolicy -Enabled $true -StartDelay 120 -WaitForHeartBeat $true | Out-Null

foreach ($vm in $jsonConfig.VMs){
    if ($vm.number){New-VMHostMulti $vm $guestPassword $vmhost $datastore}
    else {New-VMHostSingle $vm $guestPassword $vmhost $datastore}
}

Write-Host "`n`nDeployment finished. Look above for an errors with the process before hitting enter."
pause