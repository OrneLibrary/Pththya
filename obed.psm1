<#
    .SYNOPSIS
    Module file for Pththya.

    .DESCRIPTION
    Module file for Pththya.
    Contains code common to Pththya and Olmstead.

    .LINK
    Github: https://github.com/OrneLibrary/Pththya
#>



function Start-SleepCustom($Seconds,$Message) {
    <#
        .SYNOPSIS
        Sleep with message and progress banner

        .PARAMETER Seconds
        Length of sleep in seconds

        .PARAMETER Message
        Message to display in progress banner

        .EXAMPLE
        Start-SleepCustom -Seconds 30 -Message "Waiting for thing"
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

function Test-PSInterpreter{
    <#
        .SYNOPSIS
        Check is ISE is being used. Exits if ISE is detected.
    #> 

    if ($host.name -match 'Windows PowerShell ISE Host')
    {
        Write-Host "Multiple issues have been noted running this script in ISE.`nPlease use a regular script console to proceed." -ForegroundColor Red -BackgroundColor Black
        pause
        exit
    }
}


function Import-PowerCLI{
    <#
        .SYNOPSIS
        Installs and imports all PowerCLI tools from VMWare.
    #> 

    if (-not (Test-Path -Path $home\Documents\WindowsPowerShell\Modules)) { New-Item -ItemType Directory -Path $home\Documents\WindowsPowerShell\Modules }
    if ((Get-Module -ListAvailable VMware* | Measure-Object | Select-Object -ExpandProperty Count) -ne 73) {
        Write-Host "Installing VMWare Tools, this may take a while..." -ForegroundColor Cyan -BackgroundColor Black
        Save-Module -Name VMware.PowerCLI -Path $home\Documents\WindowsPowerShell\Modules
        Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP $false -Confirm:$false
    }
    Write-Host "Importing VMWare Tools, this may take a while..." -ForegroundColor Cyan -BackgroundColor Black
    Get-Module -ListAvailable VMware* | Import-Module | Out-Null
    Clear-Host

}


function Initialize-VCenter{
    <#
        .SYNOPSIS
        Connects to vCenter server.
    #> 

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

}

function Get-Node {
    <#
        .SYNOPSIS
        Gets the node to be worked on.
    #> 

    Write-Host `n`n VM Hosts:`n
    foreach ($hostName in Get-VMHost) { Write-Host $hostName }
    while ($true){
        $vmHostName = Read-Host -Prompt "Chose VM Host from the selection above"
        $vmHost = Get-VMHost -Name $vmHostName -ErrorAction SilentlyContinue
        if (-not $vmHost) { Write-Host "Host name wrong. Try again.`n" -ForegroundColor Red -BackgroundColor Black }
        else { Break }
    }
    return $vmHost

}

function Get-NodeDatastore ($vmHost) {
    <#
        .SYNOPSIS
        Gets the Datastore to be worked on.

        .PARAMETER vmhost
        VMHost object
    #> 

    Write-Host `n`nData Stores:`n
    foreach ($datastName in ($vmHost | Get-Datastore)) { Write-Host $datastName }
    while ($true) {
        $datastoreName = Read-Host -Prompt "Chose datastore from the selection above"
        $datastore = Get-Datastore -Name $datastoreName -ErrorAction SilentlyContinue
        if (-not $datastore) { Write-Host "Datastore name incorrect!!!" -ForegroundColor Red -BackgroundColor Black }
        else { Break }
    }
    return $datastore

}

function New-Network ($network,$vmhost) {
    <#
        .SYNOPSIS
        Builds new network adapter based off config file\

        .PARAMETER network
        Network dictionary based off input json

        .PARAMETER vmhost
        VMHost object
    #> 

    Write-Host "Building "$network.name
    if ($network.nic){
        New-VirtualSwitch -Name $network.name -Nic (Get-VMHostNetworkAdapter -Name $network.nic -VMHost $vmHost) -VMHost $vmHost | Out-Null
    }
    elseif ($network.nics) {
        New-VirtualSwitch -Name $network.name -Nic (Get-VMHostNetworkAdapter -Name $network.nics[0] -VMHost $vmHost) -VMHost $vmHost | Out-Null
        foreach ($nic in ($networks.nics | Select-Object -Skip 1)){
            Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch (Get-VirtualSwitch -Name $network.name -VMHost $vmHost) -VMHostPhysicalNic (Get-VMHostNetworkAdapter -Name $nic -VMHost $vmHost) -Confirm:$false
        }
        
    }

    New-VirtualPortGroup -Name $network.name -VirtualSwitch (Get-VirtualSwitch -Name $network.name  -VMHost $vmHost) | Out-Null

    if ($network.managementIP){
        New-VirtualPortGroup -Name $network.name+" Management" -VirtualSwitch (Get-VirtualSwitch -Name $network.name  -VMHost $vmHost) | Out-Null
        New-VMHostNetworkAdapter -PortGroup (Get-VirtualPortGroup -Name $network.name+" Management"  -VMHost $vmHost) -VirtualSwitch (Get-VirtualSwitch -Name $network.name  -VMHost $vmHost) -ManagementTrafficEnabled $true -IP $network.managementIP -SubnetMask $network.managementMask | Out-Null
    }

}

function New-VMHost ($vm,$vmhost,$datastore){
    <#
        .SYNOPSIS
        Builds new network adapter based off config file\

        .PARAMETER network
        Network dictionary based off input json

        .PARAMETER vmhost
        VMHost object
    #>

    Write-Host "Deploying " $vm.name
    $template = Get-Template -Name $vm.templateName
    New-VM -Name $vm.name -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
    $currentVM = Get-VM -Name $vm.name -Datastore $datastore


    if($vm.startAction -and $vm.startOrder)
    {
        Get-VMStartPolicy -VM $currentVM | Set-VMStartPolicy -StartAction PowerOn -StartOrder $vm.startOrder -StartDelay $vm.startDelay| Out-Null
    }
    elseif($vm.startAction){
        Get-VMStartPolicy -VM $currentVM | Set-VMStartPolicy -StartAction PowerOn | Out-Null
    }
    


    New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null



    # Stopped here... need to still implement all VM variables and allow for multiple of the same


}






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