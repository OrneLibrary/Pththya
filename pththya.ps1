<#
    .SYNOPSIS
    Deploys a pre-built and confiugure penetration testing environment.

    .DESCRIPTION
    Deploys a pre-built and confiugure penetration testing environment.
    Templates are not supplied in this repo. Made for 1-10 users.

    .LINK
    Github: https://github.com/OrneLibrary/Pththya
#>




function Start-Sleep-Custom($Seconds,$Message) {
    <#
        .SYNOPSIS
        SLeep with message and progress banner

        .PARAMETER Seconds
        Lenght of sleep in seconds

        .PARAMETER Message
        Message to display in progress banner

        .EXAMPLE
        Start-Sleep-Custom -Seconds 30 -Message "Waiting for thing"

    #>

    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($Seconds - $secondsLeft) / $Seconds * 100
        Write-Progress -Activity "Sleeping" -Status $Message -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Sleeping" -Status $Message -SecondsRemaining 0 -Completed
}


# Check is ISE is being used
if ($host.name -match 'Windows PowerShell ISE Host')
{
  Write-Host "Multiple issues have been noted running this script in ISE.`nPlease use a regular script console to proceed." -ForegroundColor Red -BackgroundColor Black
  pause
  exit
}


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


# Get user information and loginto vCenter
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


# Password for changing host names on the Kali and Commando boxes
$guestPassword = Read-Host -Prompt "Password for CPT account on Kali and Commando" -AsSecureString


# Get VMHost object
Write-Host `n`n VM Hosts:`n
foreach ($hostName in Get-VMHost) { Write-Host $hostName }
while ($true){
    $vmHostName = Read-Host -Prompt "Chose VM Host from the selection above"
    $vmHost = Get-VMHost -Name $vmHostName -ErrorAction SilentlyContinue
    if (-not $vmHost) { Write-Host "Host name wrong. Try again.`n" -ForegroundColor Red -BackgroundColor Black }
    else { Break }
}


# Check for correcnt default NIC configuration
while ($true){
    if ((Get-VirtualSwitch -name "vswitch0" -VMHost $vmHost | Select-Object -ExpandProperty Nic) -notmatch 'vmnic5') {
        Write-Host "vSwitch0 needs to be set to vmnic5 in the Virtual Switch tab for proper deployment.`nPlease make that configuration change before continuing."  -ForegroundColor Red -BackgroundColor Black
        pause
    }
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
# Names and order matter here as they are used as template refrences and DNS
$serverList = "PTP","C2","Share","Nessus","Planka","Mattermost","Neo4j","Utility"

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
Start-Sleep-Custom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
Invoke-VMScript -VM $currentVM -guestUser 'cpt' -guestPassword $guestPassword -ScriptText "sudo nmcli con add con-name TargetNet type ethernet ifname eth0 ipv4.method auto ipv4.ignore-auto-dns false & sudo nmcli con modify 'Wired connection 1' con-name NodeNet ifname eth1 ipv4.method auto ipv4.never-default yes ipv4.dns 172.20.20.1" | Out-Null
Invoke-VMScript -VM $currentVM -guestUser "cpt" -guestPassword $guestPassword -ScriptText "sudo hostnamectl set-hostname 'CPT-Kali' && sudo sed -i 's/kali/CPT-Kali/g' /etc/hosts && sudo gpasswd --delete cpt kali-trusted" | Out-Null
Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
Start-Sleep-Custom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
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
    Start-Sleep-Custom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
    Invoke-VMScript -VM $currentVM -guestUser "cpt" -guestPassword $guestPassword -ScriptText "sudo hostnamectl set-hostname 'Kali-$i' && sudo sed -i 's/kali/Kali-$i/g' /etc/hosts && sudo gpasswd --delete cpt kali-trusted" | Out-Null
    Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
    Start-Sleep-Custom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
    New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null
    $macCounter++
}


#Deploying CPT Commanod
Write-Host "Deploying CPT-Commando"
$template = Get-Template -Name "Commando Gold"
New-VM -Name "CPT-Commando" -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
$currentVM = Get-VM -Name "CPT-Commando"  -Datastore $datastore
$currentNIC = Get-NetworkAdapter -VM $currentVM
Set-NetworkAdapter -NetworkAdapter $currentNIC -MacAddress "00:50:56:17:90:22" -Confirm:$false | Out-Null
New-NetworkAdapter -VM $currentVM -StartConnected -NetworkName "Target" | Out-Null
Start-VM -VM $currentVM | Out-Null
Start-Sleep-Custom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
Invoke-VMScript -VM $currentVM -GuestUser "cpt" -GuestPassword $guestPassword -ScriptText "Rename-Computer -NewName 'CPT-Commando'" | Out-Null
Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
Start-Sleep-Custom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
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
    Start-Sleep-Custom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
    Invoke-VMScript -VM $currentVM -GuestUser "cpt" -GuestPassword $guestPassword -ScriptText "Rename-Computer -NewName 'Commando-$i'" | Out-Null
    Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
    Start-Sleep-Custom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
    New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null
    $macCounter++
}
Write-Host "`n`nDeployment finished. Look above for an errors with the process before hitting enter."
pause