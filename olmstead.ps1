<#
    .SYNOPSIS
    Tears down ESXi environment.

    .DESCRIPTION
    Tears down ESXi environment.
    Only thing left is vSwitch0 to allow for continued connection.

    .LINK
    Github: https://github.com/OrneLibrary/Pththya
#>


# Check is ISE is being used
if ($host.name -match 'Windows PowerShell ISE Host')
{
  Write-Host "Multiple issues have been noted running this script in ISE.`nPlease use a regular script console to proceed." -ForegroundColor Red -BackgroundColor Black
  pause
  exit
}


Write-Host "This script will remove everything from the ESXi host except the Datastore and vSwitch0.`nEnsure your connection to the ESXi host runs through vSwitch0 so the process is able to finish." -ForegroundColor Yellow -BackgroundColor Black
Pause

# Install and import PowerCli
if (-not (Test-Path -Path $home\Documents\WindowsPowerShell\Modules)) { New-Item -ItemType Directory -Path $home\Documents\WindowsPowerShell\Modules }
if ((Get-Module -ListAvailable VMware* | Measure-Object | Select-Object -ExpandProperty Count) -ne 73) {
    Write-Host "Installing VMWare Tools, this may take a while..." -ForegroundColor Cyan -BackgroundColor Black
    Save-Module -Name VMware.PowerCLI -Path $home\Documents\WindowsPowerShell\Modules
    Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP $false -Confirm:$false
}
Write-Host "Importing VMWare Tools, this may take a while..." -ForegroundColor Cyan -BackgroundColor Black
Get-Module -ListAvailable VMware* | Import-Module | Out-Null
Clear-Host


# Get user information and log into vCenter
while ($true) {
    $vCenterServer = Read-Host -Prompt "IP or FQDN of vCenter server"
    $vCenterUsername = Read-Host -Prompt "vCenter username"
    $vCenterPassword = Read-Host -Prompt "vCenter password" -AsSecureString
    $vCenterPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($vCenterPassword))
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    if (Connect-VIServer -Server $vCenterServer -Protocol https -User $vCenterUsername -Password $vCenterPassword -ErrorAction SilentlyContinue) {
        Write-Output "Connected to $vCenterServer!"
        Break
    } 
    else { $Error[0] }
}

# Get VMHost object
Write-Host `n`n VM Hosts:`n
foreach ($hostName in Get-VMHost) { Write-Host $hostName }
while ($true){
    $vmHostName = Read-Host -Prompt "Chose VM Host from the selection above"
    $vmHost = Get-VMHost -Name $vmHostName -ErrorAction SilentlyContinue
    if (-not $vmHost) { Write-Host "Host name wrong. Try again.`n" -ForegroundColor Red -BackgroundColor Black }
    else { Break }
}

# Get Datastore object
Write-Host `n`nData Stores:`n
foreach ($datastName in ($vmHost | Get-Datastore)) { Write-Host $datastName }
while ($true) {
    $datastoreName = Read-Host -Prompt "Chose datastore from the selection above"
    $datastore = Get-Datastore -Name $datastoreName -ErrorAction SilentlyContinue
    if (-not $datastore) { Write-Host "Datastore name incorrect!!!" -ForegroundColor Red -BackgroundColor Black }
    else { Break }
}

Write-Host "`n`nYou are about to delete the following:`n`nVMs:`n"
foreach ($vm in (Get-VM -Datastore $datastore)) { Write-Host $vm.name }
Write-Host "`nSwitches:"
foreach ($switch in (Get-VirtualSwitch -VMHost $vmHost)) { if ($switch.Name -ne "vSwitch0") { Write-Host $switch.Name }}
Pause
Write-Host "Shutting down all VMs"
foreach ($vm in (Get-VM -Datastore $datastore)) { Stop-VM -VM $vm }
foreach ($vm in (Get-VM -Datastore $datastore)) { Write-Host "Deleting: $vm";Remove-VM -VM $vm -DeletePermanently -Confirm:$false }
foreach ($nic in (Get-VMHostNetworkAdapter -VMHost $vmHost)){ if (@("vmk1","vmk2").contains($nic.Name)) { Write-Host "Deleting: $nic";Remove-VMHostNetworkAdapter -Nic $nic -Confirm:$false }}
foreach ($switch in (Get-VirtualSwitch -VMHost $vmHost)) { if ($switch.Name -ne "vSwitch0") {Write-Host "Deleting: $switch";Remove-VirtualSwitch -VirtualSwitch $switch -Confirm:$false }}