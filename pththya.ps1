<#
    .SYNOPSIS
    Deploys a pre-built and configure penetration testing environment.

    .DESCRIPTION
    Deploys a pre-built and configure penetration testing environment.
    Templates are not supplied in this repo. Made for 1-10 users.

    .LINK
    Github: https://github.com/OrneLibrary/Pththya
#>

Import-Module .\obed.psm1

Test-PSInterpreter
Import-PowerCLI
Initialize-VCenter
$vmHost = Get-Node
$datastore = Get-NodeDatastore -vmHost $vmHost

# Password for changing host names on the Kali and Commando boxes
$guestPassword = Read-Host -Prompt "Password for CPT account on Kali and Commando" -AsSecureString

# Check for correct default NIC configuration
while ($true){
    if ((Get-VirtualSwitch -name "vswitch0" -VMHost $vmHost | Select-Object -ExpandProperty Nic) -notmatch 'vmnic5') {
        Write-Host "vSwitch0 needs to be set to vmnic5 in the Virtual Switch tab for proper deployment.`nPlease make that configuration change before continuing."  -ForegroundColor Red -BackgroundColor Black
        pause
    }
    else { Break }
}




# Get operator network information
$pattern = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
while ($true) {
    $opNetworkIP = Read-Host -Prompt "`nEnter the IP for the Mission LAN"
    if ($opNetworkIP -match $pattern) { Break }
}
while ($true) {
    $opNetworkSub = Read-Host -Prompt "`nEnter the subnet mask for the Mission LAN (ex. 255.255.255.0)"
    if ($opNetworkSub -match $pattern) { Break }
}


# Get number of operators
while ($true) {
    [int]$numOfOperators = Read-Host -Prompt "`n`nHow many sets of operator VMs are needed (10 max)"
    if ($numOfOperators -gt 10) { Write-Host "NO... $numOfOperators is to many operators." -ForegroundColor Red -BackgroundColor Black }
    else { Break }
}


# Setting up the networking 
Write-Host "Setting up networking..."
New-VirtualSwitch -Name "cpt.local" -Nic (Get-VMHostNetworkAdapter -Name "vmnic2" -VMHost $vmHost) -VMHost $vmHost | Out-Null
Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch (Get-VirtualSwitch -Name "cpt.local" -VMHost $vmHost) -VMHostPhysicalNic (Get-VMHostNetworkAdapter -Name "vmnic3"  -VMHost $vmHost) -Confirm:$false
New-VirtualPortGroup -Name "cpt.local" -VirtualSwitch (Get-VirtualSwitch -Name "cpt.local"  -VMHost $vmHost) | Out-Null
New-VirtualPortGroup -Name "cpt.local Management" -VirtualSwitch (Get-VirtualSwitch -Name "cpt.local"  -VMHost $vmHost) | Out-Null
New-VMHostNetworkAdapter -PortGroup (Get-VirtualPortGroup -Name "cpt.local Management"  -VMHost $vmHost) -VirtualSwitch (Get-VirtualSwitch -Name "cpt.local"  -VMHost $vmHost) -ManagementTrafficEnabled $true -IP "172.20.20.2" -SubnetMask "255.255.255.0" | Out-Null


New-VirtualSwitch -Name "Cell Router" -Nic (Get-VMHostNetworkAdapter -Name "vmnic1" -VMHost $vmHost) -VMHost $vmHost | Out-Null
New-VirtualPortGroup -Name "Cell Router" -VirtualSwitch (Get-VirtualSwitch -Name "Cell Router"  -VMHost $vmHost) | Out-Null


New-VirtualSwitch -Name "Target" -Nic (Get-VMHostNetworkAdapter -Name "vmnic0" -VMHost $vmHost) -VMHost $vmHost | Out-Null
New-VirtualPortGroup -Name "Target" -VirtualSwitch (Get-VirtualSwitch -Name "Target"  -VMHost $vmHost) | Out-Null

New-VirtualSwitch -Name "Mission LAN" -Nic (Get-VMHostNetworkAdapter -Name "vmnic4" -VMHost $vmHost) -VMHost $vmHost | Out-Null
New-VirtualPortGroup -Name "Mission LAN" -VirtualSwitch (Get-VirtualSwitch -Name "Mission LAN"  -VMHost $vmHost) | Out-Null
New-VMHostNetworkAdapter -PortGroup (Get-VirtualPortGroup -Name "Mission LAN"  -VMHost $vmHost) -VirtualSwitch (Get-VirtualSwitch -Name "Mission LAN"  -VMHost $vmHost) -ManagementTrafficEnabled $true -IP "$opNetworkIP" -SubnetMask "$opNetworkSub" | Out-Null


# Allowing autostart of VMs
Get-VMHostStartPolicy -VMHost $vmHost | Set-VMHostStartPolicy -Enabled $true -StartDelay 120 -WaitForHeartBeat $true | Out-Null


# Deploying pfSense
Write-Host "Deploying pfSense"
$template = Get-Template -Name "pfSense Gold"
$server = "pfSense"
New-VM -Name $server -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
$currentVM = Get-VM -Name $server -Datastore $datastore
Get-VMStartPolicy -VM $currentVM | Set-VMStartPolicy -StartAction PowerOn -StartOrder 1 -StartDelay 120| Out-Null
New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null


# List of all servers.
# Names and order matter here as they are used as template references and DNS
$serverList = "PTP","C2","Share","Nessus","Planka","Mattermost","Neo4j","GoPhish","Utility"

$macCounter = 10
# Loop to deploy servers
foreach ($server in $serverList) {
    Write-Host "Deploying $server"
    $template = Get-Template -Name "$server Gold"
    $server = $server
    New-VM -Name $server -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
    $currentVM = Get-VM -Name $server -Datastore $datastore
    $currentNIC = Get-NetworkAdapter -VM $currentVM
    Set-NetworkAdapter -NetworkAdapter $currentNIC -MacAddress "00:50:56:17:90:$macCounter" -Confirm:$false | Out-Null
    Get-VMStartPolicy -VM $currentVM | Set-VMStartPolicy -StartAction PowerOn | Out-Null
    New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null
    $macCounter++
}


# Deploying CPT Kali 
Write-Host "Deploying CPT-Kali"
$template = Get-Template -Name "Kali Gold"
New-VM -Name "CPT-Kali" -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
$currentVM = Get-VM -Name "CPT-Kali"  -Datastore $datastore
$currentNIC = Get-NetworkAdapter -VM $currentVM
Set-NetworkAdapter -NetworkAdapter $currentNIC -MacAddress "00:50:56:17:90:21" -Confirm:$false | Out-Null
New-NetworkAdapter -VM $currentVM -StartConnected -NetworkName "Target" | Out-Null
Start-VM -VM $currentVM | Out-Null
Start-SleepCustom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
Invoke-VMScript -VM $currentVM -guestUser 'cpt' -guestPassword $guestPassword -ScriptText "sudo nmcli con add con-name TargetNet type ethernet ifname eth0 ipv4.method auto ipv4.ignore-auto-dns false & sudo nmcli con modify 'Wired connection 1' con-name NodeNet ifname eth1 ipv4.method auto ipv4.never-default yes ipv4.dns 172.20.20.1" | Out-Null
Invoke-VMScript -VM $currentVM -guestUser "cpt" -guestPassword $guestPassword -ScriptText "sudo hostnamectl set-hostname 'CPT-Kali' && sudo sed -i 's/kali/CPT-Kali/g' /etc/hosts && sudo gpasswd --delete cpt kali-trusted" | Out-Null
Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
Start-SleepCustom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null


# Deploying Kalis
$macCounter = 30
for ($i=0 ; $i -lt $numOfOperators ; $i++) {
    Write-Host "Deploying Kali-$i"
    New-VM -Name "Kali-$i" -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
    $currentVM = Get-VM -Name "Kali-$i"  -Datastore $datastore
    $currentNIC = Get-NetworkAdapter -VM $currentVM
    Set-NetworkAdapter -NetworkAdapter $currentNIC -MacAddress "00:50:56:17:90:$macCounter" -Confirm:$false | Out-Null
    Start-VM -VM $currentVM | Out-Null
    Start-SleepCustom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
    Invoke-VMScript -VM $currentVM -guestUser "cpt" -guestPassword $guestPassword -ScriptText "sudo hostnamectl set-hostname 'Kali-$i' && sudo sed -i 's/kali/Kali-$i/g' /etc/hosts && sudo gpasswd --delete cpt kali-trusted" | Out-Null
    Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
    Start-SleepCustom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
    New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null
    $macCounter++
}


#Deploying CPT Commando
Write-Host "Deploying CPT-Commando"
$template = Get-Template -Name "Commando Gold"
New-VM -Name "CPT-Commando" -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
$currentVM = Get-VM -Name "CPT-Commando"  -Datastore $datastore
$currentNIC = Get-NetworkAdapter -VM $currentVM
Set-NetworkAdapter -NetworkAdapter $currentNIC -MacAddress "00:50:56:17:90:22" -Confirm:$false | Out-Null
New-NetworkAdapter -VM $currentVM -StartConnected -NetworkName "Target" | Out-Null
Start-VM -VM $currentVM | Out-Null
Start-SleepCustom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
Invoke-VMScript -VM $currentVM -GuestUser "cpt" -GuestPassword $guestPassword -ScriptText "Rename-Computer -NewName 'CPT-Commando'" | Out-Null
Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
Start-SleepCustom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null


# Deploying Commandos
$macCounter = 40
for ($i=0 ; $i -lt $numOfOperators ; $i++) {
    Write-Host "Deploying Commando-$i"
    New-VM -Name "Commando-$i" -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
    $currentVM = Get-VM -Name "Commando-$i"  -Datastore $datastore
    $currentNIC = Get-NetworkAdapter -VM $currentVM
    Set-NetworkAdapter -NetworkAdapter $currentNIC -MacAddress "00:50:56:17:90:$macCounter" -Confirm:$false | Out-Null
    Start-VM -VM $currentVM | Out-Null
    Start-SleepCustom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
    Invoke-VMScript -VM $currentVM -GuestUser "cpt" -GuestPassword $guestPassword -ScriptText "Rename-Computer -NewName 'Commando-$i'" | Out-Null
    Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
    Start-SleepCustom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
    New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null
    $macCounter++
}
Write-Host "`n`nDeployment finished. Look above for an errors with the process before hitting enter."
pause