# Adapted from https://github.com/parsec-cloud/Cloud-GPU-Updater/blob/master/GPUUpdaterTool.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
  if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
   $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
   Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
   Exit
  }
}

function prepareEnvironment {
    $Test = Test-Path -Path $System.Path 
    if ($Test -eq $true) {
        Remove-Item -path $System.Path -Recurse -Force | Out-Null
        New-Item -ItemType Directory -Force -Path $System.Path | Out-Null
        }
    Else {
        New-Item -ItemType Directory -Force -Path $System.Path | Out-Null
        }
}
 
function installedGPUID {
    #queries WMI to get DeviceID of the installed NVIDIA GPU
    Try {
        (get-wmiobject -query "select DeviceID from Win32_PNPEntity Where (deviceid Like '%PCI\\VEN_10DE%') and (PNPClass = 'Display' or Name = '3D Video Controller')"  | Select-Object DeviceID -ExpandProperty DeviceID).substring(13,8)
        }
    Catch {}
    Try {
        (get-wmiobject -query "select DeviceID from Win32_PNPEntity Where (deviceid Like '%PCI\\VEN_1002%')"  | Select-Object DeviceID -ExpandProperty DeviceID).substring(13,8)
    }
    Catch {}
}


Function latestDriver {
    # g3 
    If($gpu.deviceId -eq "DEV_13F2"){
        $s3path = $(([xml](invoke-webrequest -uri https://ec2-windows-nvidia-drivers.s3.amazonaws.com).content).listbucketresult.contents.key -like  "latest/*server2019*") 
        $s3path.split('_')[0].split('/')[1]
        }
    ElseIf($gpu.deviceId -eq "DEV_1EB8"){
        s3DriverObject -GPU "G4dn"| Out-Null
        $G4WebDriver = s3DriverObject -GPU "G4dn"
        $G4WebDriver.tostring().split('-')[1]
        }
    ElseIf($gpu.deviceId -eq "DEV_7362"){
        s3DriverObject -GPU "G4ad"| Out-Null
        $G4WebDriver = s3DriverObject -GPU "G4ad"
        $G4WebDriver.tostring().split('/')[1].split('-')[0]
        }
    ElseIf($gpu.deviceId -eq "DEV_2237"){
        s3DriverObject -GPU "G5"| Out-Null
        $G5WebDriver = s3DriverObject -GPU "G5"
        $G5WebDriver.tostring().split('-')[1]
        }
    }
 
Function s3DriverObject {
    param (
        $GPU    
    )
    If (($GPU -eq "G4dn") -or ($GPU -eq "G5")){
        $Bucket = "nvidia-gaming"
        $KeyPrefix = "windows/latest"
        $S3Objects = Get-S3Object -BucketName $Bucket -KeyPrefix $KeyPrefix -Region us-east-1
        $S3Objects.key | select-string -Pattern '.zip' 
    }
    ElseIf ($GPU -eq "G4ad"){
        $Bucket = "ec2-amd-windows-drivers"
        $KeyPrefix = "latest"
        $S3Objects = Get-S3Object -BucketName $Bucket -KeyPrefix $KeyPrefix -Region us-east-1
        $S3Objects.key | select-string -Pattern '.zip'
    }
}
 
function queryOS {
    #sets OS support
    If (($system.OS_Version -like "*Server 2019*") -eq $true) {$gpu.OSID = "119"; $system.OS_Supported = $true}
    Elseif (($system.OS_Version -like "*Server 2022*") -eq $true) {$gpu.OSID = "134"; $system.OS_Supported = $true}
    Else {$system.OS_Supported = $false}
}

function queryGPU {
    If($gpu.deviceId -eq "DEV_13F2") {$gpu.Name = 'NVIDIA Tesla M60'; } 
    ElseIf($gpu.deviceId -eq "DEV_1BB3") {$gpu.Name = 'NVIDIA Tesla P4'; }
    ElseIf($gpu.deviceId -eq "DEV_1EB8") {$gpu.Name = 'NVIDIA Tesla T4'; }
    ElseIf($gpu.deviceId -eq "DEV_2237") {$gpu.Name = 'NVIDIA A10G'; }
    ElseIf($gpu.deviceId -eq "DEV_7362") {$gpu.Name = 'AMD Radeon Pro V520';} 
    Else {$gpu.Name = "No Device Found or Unsupported"} 
}

function downloadDriver {
    If($gpu.deviceId -eq "DEV_13F2"){
        $s3path = $(([xml](invoke-webrequest -uri https://ec2-windows-nvidia-drivers.s3.amazonaws.com).content).listbucketresult.contents.key -like  "latest/*server2019*") 
        (New-Object System.Net.WebClient).DownloadFile($("https://ec2-windows-nvidia-drivers.s3.amazonaws.com/" + $s3path), $($system.Path) + "\NVIDIA_" + $($gpu.latestDriver) + ".exe")
    }
    ElseIf(($gpu.deviceId -eq "DEV_1EB8") -or ($gpu.deviceId -eq "DEV_2237")){
        If($gpu.deviceId -eq "DEV_1EB8"){
            $S3Path = s3DriverObject -GPU "G4dn"
        }
        ElseIf($gpu.deviceId -eq "DEV_2237"){
            $S3Path = s3DriverObject -GPU "G5"
        }

        (New-Object System.Net.WebClient).DownloadFile($("https://nvidia-gaming.s3.amazonaws.com/" + $s3path), $($system.Path) + "\NVIDIA_" + $($gpu.latestDriver) + ".zip")
        Expand-Archive -Path ($($system.Path) + "\NVIDIA_" + $($gpu.latestDriver) + ".zip") -DestinationPath "$($system.Path)\ExtractedGPUDriver\"
        $extractedpath = Get-ChildItem -Path "$($system.Path)\ExtractedGPUDriver\" | Where-Object name -like '*win10*' | % name
        Rename-Item -Path "$($system.Path)\ExtractedGPUDriver\$extractedpath" -NewName "NVIDIA_$($gpu.latestDriver).exe"
        Move-Item -Path "$($system.Path)\ExtractedGPUDriver\NVIDIA_$($gpu.latestDriver).exe" -Destination $system.Path
        remove-item "$($system.Path)\NVIDIA_$($gpu.latestDriver).zip"
        remove-item "$($system.Path)\ExtractedGPUDriver" -Recurse
        (New-Object System.Net.WebClient).DownloadFile("https://nvidia-gaming.s3.amazonaws.com/GridSwCert-Archive/GridSwCert-Windows_2020_04.cert", "C:\Users\Public\Documents\GridSwCert.txt")

    }
    Elseif($gpu.deviceId -eq "DEV_7362"){
        $S3Path = s3DriverObject -GPU "G4ad"
        (New-Object System.Net.WebClient).DownloadFile($("https://ec2-amd-windows-drivers.s3.amazonaws.com/" + $s3path), $($system.Path) + "\AMD_" + $($gpu.latestDriver) + ".zip")
        Expand-Archive -Path ($($system.Path) + "\AMD_" + $($gpu.latestDriver) + ".zip") -DestinationPath "$($system.Path)\ExtractedGPUDriver\"
        $GPU.AMDExtractedPath = Get-ChildItem -Path "$($system.Path)\ExtractedGPUDriver\" -recurse -Directory | Where-Object name -like '*WT6A_INF*' | % FullName
    }
}

function Test-RegistryValue {
    # https://www.jonathanmedd.net/2014/02/testing-for-the-presence-of-a-registry-key-and-value.html
    param (

     [parameter(Mandatory=$true)]
     [ValidateNotNullOrEmpty()]$Path,

    [parameter(Mandatory=$true)]
     [ValidateNotNullOrEmpty()]$Value
    )
    try {
        Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Value -ErrorAction Stop | Out-Null
        return $true
        }
    catch {
        return $false
        }

}

function installDriver {
    #installs driver silently with /s /n arguments provided by NVIDIA
    # g3 / g4dn / g5
    If (($gpu.deviceId -eq "DEV_13F2") -or ($gpu.deviceId -eq "DEV_2237") -or ($gpu.deviceId -eq "DEV_2237")) {
        $DLpath = Get-ChildItem -Path $system.path -Include *exe* -Recurse | Select-Object -ExpandProperty Name
        Start-Process -FilePath "$($system.Path)\$dlpath" -ArgumentList "/s /n" -Wait 
        # g4dn / g5
        If (($gpu.deviceId -eq "DEV_1EB8") -or ($gpu.deviceId -eq "DEV_2237")) {
            If((Test-RegistryValue -path 'HKLM:\SOFTWARE\NVIDIA Corporation\Global' -value 'vGamingMarketplace') -eq $true) {
                Set-itemproperty -path 'HKLM:\SOFTWARE\NVIDIA Corporation\Global' -Name "vGamingMarketplace" -Value "2" | Out-Null
            } Else {
                New-ItemProperty -path 'HKLM:\SOFTWARE\NVIDIA Corporation\Global' -Name "vGamingMarketplace" -Value "2" -PropertyType DWORD | Out-Null
            }
        }
        ElseIf ($gpu.deviceId -eq "DEV_13F2") {
             If((Test-RegistryValue -path 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\GridLicensing' -value 'NvCplDisableManageLicensePage') -eq $true) {
                Set-ItemProperty -Path "HKLM:\SOFTWARE\NVIDIA Corporation\Global\GridLicensing" -Name "NvCplDisableManageLicensePage" -Value "1" | Out-Null
             } Else {
                New-ItemProperty -Path "HKLM:\SOFTWARE\NVIDIA Corporation\Global\GridLicensing" -Name "NvCplDisableManageLicensePage"  -Value "1" -PropertyType DWORD | Out-Null
             }
        }
    }
    Else { #g4ad
        pnputil /add-driver $($GPU.AMDExtractedPath+ "\*inf") /install | out-null
    }
}

$gpu = @{deviceId = installedGPUID; latestDriver = latestDriver}
$system = @{Path = "C:\Drivers"}

prepareEnvironment
queryOS
querygpu
downloadDriver
installDriver
Restart-Computer -Force