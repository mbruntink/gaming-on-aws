# Adapted from https://github.com/parsec-cloud/Cloud-GPU-Updater/blob/master/GPUUpdaterTool.ps1
# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
     $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
     Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
     Exit
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

function queryGPU {
    If($gpu.deviceId -eq "DEV_13F2") {$gpu.Name = 'NVIDIA Tesla M60'; } 
    ElseIf($gpu.deviceId -eq "DEV_1BB3") {$gpu.Name = 'NVIDIA Tesla P4'; }
    ElseIf($gpu.deviceId -eq "DEV_1EB8") {$gpu.Name = 'NVIDIA Tesla T4'; }
    ElseIf($gpu.deviceId -eq "DEV_7362") {$gpu.Name = 'AMD Radeon Pro V520';} 
    Else {$gpu.Name = "No Device Found or Unsupported"} 
}

function optimizeGPU {
    # https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/optimize_gpu.html
    If(@("DEV_13F2", "DEV_1EB8", "DEV_2237") -contains $gpu.deviceId){
    
        If($gpu.deviceId -eq "DEV_13F2"){
            #g3
            $nvidiaarg = "--auto-boost-default=0 -ac '2505,1177'"      
        }
        ElseIf($gpu.deviceId -eq "DEV_1EB8"){
            #g4dn
            $nvidiaarg = "-ac '5001,15907'" 
        }  
        ElseIf($gpu.deviceId -eq "DEV_2237"){
            #g5
            $nvidiaarg = "-ac '6250,1710'" 
        }
        $nvidiasmi = "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi"
        Invoke-Expression "& `"$nvidiasmi`" $nvidiaarg"
    }
}
  
$gpu = @{deviceId = installedGPUID;}
queryGPU
optimizeGPU
