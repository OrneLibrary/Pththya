<#
    .SYNOPSIS
    Tears down ESXi environment.

    .DESCRIPTION
    Tears down ESXi environment.
    Only thing left is vSwitch0 to allow for continued connection.

    .LINK
    Github: https://github.com/OrneLibrary/Pththya
#>

Import-Module .\obed.psm1

Write-Host "This script will remove everything from the ESXi host except the Datastore and vSwitch0.`nEnsure your connection to the ESXi host runs through vSwitch0 so the process is able to finish." -ForegroundColor Yellow -BackgroundColor Black
Pause

Test-PSInterpreter
Import-PowerCLI
Initialize-VCenter
$vmHost = Get-Node
$datastore = Get-NodeDatastore -vmHost $vmHost

Write-Host "`n`nYou are about to delete the following:`n`nVMs:`n"
foreach ($vm in (Get-VM -Datastore $datastore)) { Write-Host $vm.name }
Write-Host "`nSwitches:"
foreach ($switch in (Get-VirtualSwitch -VMHost $vmHost)) { if ($switch.Name -ne "vSwitch0") { Write-Host $switch.Name } }
Pause
Write-Host "Shutting down all VMs"
foreach ($vm in (Get-VM -Datastore $datastore)) { if ($vm.PowerState -eq "PoweredOn") { Stop-VM -VM $vm -Confirm:$false } }
foreach ($vm in (Get-VM -Datastore $datastore)) { Write-Host "Deleting: $vm"; Remove-VM -VM $vm -DeletePermanently -Confirm:$false }
foreach ($template in (Get-Template -Datastore $datastore)) { Write-Host "Deleting: $template", Remove-Template -Template $template -Confirm:$false }
foreach ($nic in (Get-VMHostNetworkAdapter -VMHost $vmHost)) { if (@("vmk1", "vmk2").contains($nic.Name)) { Write-Host "Deleting: $nic"; Remove-VMHostNetworkAdapter -Nic $nic -Confirm:$false } }
foreach ($switch in (Get-VirtualSwitch -VMHost $vmHost)) { if ($switch.Name -ne "vSwitch0") { Write-Host "Deleting: $switch"; Remove-VirtualSwitch -VirtualSwitch $switch -Confirm:$false } }