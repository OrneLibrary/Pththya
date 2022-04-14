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
        Check is ISE is being used. Exits if ISE is detected
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
        Installs and imports all PowerCLI tools from VMWare
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


function Initialize-VCenter($config){
    <#
        .SYNOPSIS
        Connects to vCenter server

        .PARAMETER config
        Configuration for login details
    #> 

    while ($true) {
        $vCenterServer = if ($config.vcenterServer) {$config.vcenterServer} else {Read-Host -Prompt "IP or FQDN of vCenter server"}
        $vCenterUsername = if ($config.vcenterUser) {$config.vcenterUser} else {Read-Host -Prompt "vCenter username"}
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

function Get-Node ($config){
    <#
        .SYNOPSIS
        Gets the node to be worked on

        .PARAMETER config
        Configuration for login details
    #> 

    if ($config.vmHost){
        Write-Host "Attempting connection to " $config.vmHost
        $vmHost = Get-VMHost -Name $config.vmHost -ErrorAction SilentlyContinue
        if (-not $vmHost) { Write-Host "Host name in config file wrong. Please set manually.`n`n" -ForegroundColor Red -BackgroundColor Black }
        else {return $vmHost}
    }

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

function Get-NodeDatastore ($vmHost,$config) {
    <#
        .SYNOPSIS
        Gets the Datastore to be worked on

        .PARAMETER vmhost
        VMHost object

        .PARAMETER config
        Configuration for login details
    #> 

    if ($config.vmDatastore){
        Write-Host "Attempting to mount " $config.vmDatastore
        $datastore = Get-Datastore -Name $config.vmDatastore -ErrorAction SilentlyContinue
        if (-not $datastore) { Write-Host "Datastore name in config file wrong. Please set manually.`n`n" -ForegroundColor Red -BackgroundColor Black }
        else {return $datastore}
    }
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
        Builds new network adapter based off config file

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

function New-VMHostSingle ($vm,$guestPassword,$vmhost,$datastore){
    <#
        .SYNOPSIS
        Builds single VM based off config

        .PARAMETER vm
        VM dictionary based off input json

        .PARAMETER guestPassword
        Password used to run commands on VM

        .PARAMETER vmhost
        VMHost object

        .PARAMETER datastore
        Datastore object
    #>

    Write-Host "Deploying " $vm.name
    $template = Get-Template -Name $vm.templateName
    New-VM -Name $vm.name -Template $template -Datastore $datastore -DiskStorageFormat Thin -VMHost $vmHost | Out-Null
    $currentVM = Get-VM -Name $vm.name -Datastore $datastore

    if ($vm.startAction -and $vm.startOrder)
    {
        Get-VMStartPolicy -VM $currentVM | Set-VMStartPolicy -StartAction PowerOn -StartOrder $vm.startOrder -StartDelay $vm.startDelay| Out-Null
    }
    elseif ($vm.startAction){
        Get-VMStartPolicy -VM $currentVM | Set-VMStartPolicy -StartAction PowerOn | Out-Null
    }
    
    if ($vm.mac){
        $currentNIC = Get-NetworkAdapter -VM $currentVM
        Set-NetworkAdapter -NetworkAdapter $currentNIC -MacAddress $vm.mac -Confirm:$false | Out-Null
    }

    if ($vm.networkAdapter){
        foreach ($adapter in $vm.networkAdapter){
            New-NetworkAdapter -VM $currentVM -StartConnected -NetworkName $adapter | Out-Null
        }
    }

    if ($vm.commands){
        Start-VM -VM $currentVM | Out-Null
        Start-SleepCustom -Seconds 60 -Message "Waiting for $currentVM to fully boot..."
        foreach ($command in $vm.commands){
            Invoke-VMScript -VM $currentVM -guestUser $vm.userName -guestPassword $guestPassword -ScriptText $command | Out-Null
            
        }
        Shutdown-VMGuest -VM $currentVM -Confirm:$false | Out-Null
        Start-SleepCustom -Seconds 10 -Message "Waiting for $currentVM to fully shutdown..."
    }

    New-Snapshot -VM $currentVM -Name "Gold" -Description "Lab provided Gold image" | Out-Null
}

function New-VMHostMulti($vm,$guestPassword,$vmhost,$datastore){
    <#
        .SYNOPSIS
        Loops through building multiple VMs

        .PARAMETER network
        VM dictionary based off input json

        .PARAMETER vmhost
        VMHost object

        .PARAMETER datastore
        Datastore object
    #>
    if($vm.number){
        for($i=0 ; $i -lt $vm.number ; $i++){
            $currentVM = @{
                name = $vm.name+"-"+$i;
                templateName = $vm.templateName;
                mac = $vm.macStart.Substring(0,15)+([int]$vm.macStart.Split(":")[5]+1);
                startAction = $vm.startAction;
                startOrder = $vm.startOrder;
                startDelay = $vm.startDelay;
                networkAdapter = $vm.networkAdapter;
                commands = $vm.commands;
                userName = $vm.userName;
                counter = $i
            }
            New-VMHostSingle $currentVM $guestPassword $vmhost $datastore
        }
    }
}