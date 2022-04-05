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

}

function Get-NodeDatastore{
    <#
        .SYNOPSIS
        Gets the Datastore to be worked on.
    #> 

    Write-Host `n`nData Stores:`n
    foreach ($datastName in ($vmHost | Get-Datastore)) { Write-Host $datastName }
    while ($true) {
        $datastoreName = Read-Host -Prompt "Chose datastore from the selection above"
        $datastore = Get-Datastore -Name $datastoreName -ErrorAction SilentlyContinue
        if (-not $datastore) { Write-Host "Datastore name incorrect!!!" -ForegroundColor Red -BackgroundColor Black }
        else { Break }
    }

}