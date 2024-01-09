
function HVConvertIecUnitToLong
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$IecValue
    )

    [int]$decValue = [regex]::Match($IecValue, "\d*").Value
    [string]$IecUnit = [regex]::Match($IecValue, "[A-Za-z]+").Value
    [int]$power = 1

    switch ($IecUnit) {
        "KiB" {
            $power = 1
        }
        "MiB" {
            $power = 2
        }
        "GiB" {
            $power = 3
        }
        "TiB" {
            $power = 4
        }
        default {
            return -1
        }
    }

    return ([long]($decValue * [math]::Pow(1024, $power)))
}

# About PSSession
# For Linux: SSH connection
#            The name of VM is not real-name, using IP address of VM
function HV-PSSessionCreate
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName,

        [Parameter(Mandatory=$True)]
        [string]$PSName,

        [bool]$IsWin = $true,

        [bool]$CheckFlag = $true
    )

    HV-WaitVMToCompleted -VMName $VMName -Wait $false | out-null

    if ($IsWin) {
        $VMNameReal = $VMName
    } else {
        $VMNameReal = HV-GetVMIPAddress -VMName $VMName
        $KeyFilePath = "{0}\\{1}" -f $SSHKeys.Path, $SSHKeys.PrivateKeyName
    }

    $PSSessionStatus = HV-PSSessionCheck -VMName $VMNameReal -PSName $PSName
    if (-not $PSSessionStatus.result) {
        if ($PSSessionStatus.exist) {
            HV-PSSessionRemove -PSName $PSName | out-null
        }

        Win-DebugTimestamp -output ("Create PS session named {0} for VM named {1}" -f $PSName, $VMNameReal)

        for ($i = 1; $i -lt 50; $i++) {
            try {
                $PSSessionError = $null
                if ($IsWin) {
                    New-PSSession `
                        -VMName $VMNameReal `
                        -Credential $WTWCredentials `
                        -Name $PSName `
                        -ErrorAction SilentlyContinue `
                        -ErrorVariable ProcessError | out-null
                } else {
                    New-PSSession `
                        -HostName $VMNameReal `
                        -UserName $RemoteUserConfig.RootName `
                        -KeyFilePath $KeyFilePath `
                        -Name $PSName `
                        -ErrorAction SilentlyContinue `
                        -ErrorVariable ProcessError | out-null
                }

                Start-Sleep -Seconds 5

                $PSSessionStatus = HV-PSSessionCheck -VMName $VMNameReal -PSName $PSName
                if ($PSSessionStatus.result) {
                    Win-DebugTimestamp -output ("Creating PS seesion is successful > {0}" -f $PSName)
                    break
                }
            } catch {
                Win-DebugTimestamp -output ("Creating PS seesion is failed and try again > {0}" -f $i)
                continue
            }
        }

        if ($IsWin -and $CheckFlag) {
            $Session = Get-PSSession -name $PSName
            if (Invoke-Command -Session $Session -ScriptBlock {
                    Param($SiteKeep)
                    Test-Path -Path $SiteKeep.DumpFile
                } -ArgumentList $SiteKeep) {
                $Remote2HostDumpFile = "{0}\\dump_{1}_{2}.DMP" -f
                    $LocationInfo.BertaResultPath,
                    $VMNameReal.split("_")[1],
                    $LocationInfo.TestCaseName
                Copy-Item -FromSession $Session `
                          -Path $SiteKeep.DumpFile `
                          -Destination $Remote2HostDumpFile `
                          -Force `
                          -Confirm:$false | out-null

                Invoke-Command -Session $Session -ScriptBlock {
                    Param($SiteKeep)
                    Get-Item -Path $SiteKeep.DumpFile | Remove-Item -Recurse
                } -ArgumentList $SiteKeep
            }

            $LocationInfo.PDBNameArray.Remote | ForEach-Object {
                $BertaEtlFile = "{0}\\Tracelog_{1}_{2}_{3}.etl" -f
                    $LocationInfo.BertaResultPath,
                    $_,
                    $VMNameReal.split("_")[1],
                    $LocationInfo.TestCaseName
                $RemoteEtlFile = $TraceLogOpts.EtlFullPath[$_]
                if (Invoke-Command -Session $Session -ScriptBlock {
                        Param($RemoteEtlFile)
                        Test-Path -Path $RemoteEtlFile
                    } -ArgumentList $RemoteEtlFile) {
                    Copy-Item -FromSession $Session `
                              -Path $RemoteEtlFile `
                              -Destination $BertaEtlFile `
                              -Force `
                              -Confirm:$false | out-null

                    Invoke-Command -Session $Session -ScriptBlock {
                        Param($RemoteEtlFile)
                        Get-Item -Path $RemoteEtlFile | Remove-Item -Recurse
                    } -ArgumentList $RemoteEtlFile
                }
            }
        }
    }

    return (Get-PSSession -name $PSName)
}

function HV-PSSessionRemove
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$PSName
    )

    $PSSessionError = $null
    Remove-PSSession `
        -Name $PSName `
        -ErrorAction SilentlyContinue `
        -ErrorVariable ProcessError | out-null
}

function HV-PSSessionCheck
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName,

        [Parameter(Mandatory=$True)]
        [string]$PSName
    )

    $ReturnValue = [hashtable] @{
        result = $false
        exist = $false
    }

    $PSSessionError = $null
    $PSSession = Get-PSSession `
        -Name $PSName `
        -ErrorAction SilentlyContinue `
        -ErrorVariable ProcessError

    if ([String]::IsNullOrEmpty($PSSessionError)) {
        if ($PSSession.ComputerName -eq $VMName) {
            if ($PSSession.state -eq "Opened") {
                $ReturnValue.result = $true
                $ReturnValue.exist = $true
            } else {
                $ReturnValue.result = $false
                $ReturnValue.exist = $true
            }
        } else {
            $ReturnValue.result = $false
            $ReturnValue.exist = $true
        }
    } else {
        $ReturnValue.result = $false
        $ReturnValue.exist = $false
    }

    return $ReturnValue
}

# About VMVFOSConfigs
function HV-GenerateVMVFConfig
{
    Param(
        [string]$ConfigType = "Base_Parameter",

        [hashtable]$RemoteInfo = $null
    )

    $ReturnValue = @()

    if ($LocationInfo.VM.IsWin) {
        if (($ConfigType -eq "SmokeTest") -or ($ConfigType -eq "Stress") -or ($ConfigType -eq "LiveM")) {
            $VMOSs = ("windows2022")
        } else {
            $VMOSs = ("windows2019", "windows2022")
        }
    } else {
        $VMOSs = ("ubuntu2004")
    }

    Foreach ($VMOS in $VMOSs) {
        if (($ConfigType -eq "Base_Parameter") -or
            ($ConfigType -eq "Base_Compat") -or
            ($ConfigType -eq "Performance_Parameter") -or
            ($ConfigType -eq "Installer") -or
            ($ConfigType -eq "Fallback")) {
            if (($ConfigType -eq "Base_Parameter") -or
                ($ConfigType -eq "Base_Compat") -or
                ($ConfigType -eq "Installer") -or
                ($ConfigType -eq "Fallback")) {
                $VMVFOSName = "3vm_{0}vf_{1}" -f $LocationInfo.PF.Number, $VMOS
                $ReturnValue += $VMVFOSName
            }

            $AllVFs = $LocationInfo.PF.Number * $LocationInfo.PF2VF
            $VMNumber = [Math]::Truncate($AllVFs / 64)
            if ($VMNumber -gt 2) {$VMNumber = 2}
            $VMVFOSName = "{0}vm_64vf_{1}" -f $VMNumber, $VMOS
            $ReturnValue += $VMVFOSName
        } elseif ($ConfigType -eq "Performance") {
            $VMVFOSName = "1vm_{0}vf_{1}" -f ($LocationInfo.PF.Number * 2), $VMOS
            $ReturnValue += $VMVFOSName
        } elseif ($ConfigType -eq "SmokeTest") {
            $VMVFOSName = "1vm_{0}vf_{1}" -f $LocationInfo.PF.Number, $VMOS
            $ReturnValue += $VMVFOSName
        } elseif ($ConfigType -eq "Stress") {
            $VMVFOSName = "12vm_{0}vf_{1}" -f $LocationInfo.PF.Number, $VMOS
            $ReturnValue += $VMVFOSName
        } elseif ($ConfigType -eq "LiveM") {
            if ([String]::IsNullOrEmpty($RemoteInfo)) {
                $VMVFOSName = "3vm_{0}vf_{1}" -f $LocationInfo.PF.Number, $VMOS
                $ReturnValue += $VMVFOSName

                $AllVFs = $LocationInfo.PF.Number * $LocationInfo.PF2VF
                $VMNumber = [Math]::Truncate($AllVFs / 64)
                if ($VMNumber -gt 1) {$VMNumber = 1}
                $VMVFOSName = "{0}vm_64vf_{1}" -f $VMNumber, $VMOS
                $ReturnValue += $VMVFOSName
            } else {
                if ($LocationInfo.PF.Number -gt $RemoteInfo.PF.Number) {
                    $PFNumber = $RemoteInfo.PF.Number
                } else {
                    $PFNumber = $LocationInfo.PF.Number
                }
                $VMVFOSName = "3vm_{0}vf_{1}" -f $PFNumber, $VMOS
                $ReturnValue += $VMVFOSName

                $LocationAllVFs = $LocationInfo.PF.Number * $LocationInfo.PF2VF
                $LocationVMNumber = [Math]::Truncate($LocationAllVFs / 64)
                $RemoteAllVFs = $RemoteInfo.PF.Number * $RemoteInfo.PF2VF
                $RemoteVMNumber = [Math]::Truncate($RemoteAllVFs / 64)
                if ($LocationVMNumber -gt $RemoteVMNumber) {
                    $VMNumber = $RemoteVMNumber
                } else {
                    $VMNumber = $LocationVMNumber
                }
                if ($VMNumber -gt 1) {$VMNumber = 1}
                $VMVFOSName = "{0}vm_64vf_{1}" -f $VMNumber, $VMOS
                $ReturnValue += $VMVFOSName
            }
        } elseif ($ConfigType -eq "Gtest") {
            $VMVFOSName = "3vm_{0}vf_{1}" -f $LocationInfo.PF.Number, $VMOS
            $ReturnValue += $VMVFOSName
        } else {
            throw ("Can not generate VMVFOS configs > {0}" -f $ConfigType)
        }
    }

    Win-DebugTimestamp -output ("Generate VMVFOS configs:")
    Foreach ($VMVFOS in $ReturnValue) {
        Win-DebugTimestamp -output ("    --> {0}" -f $VMVFOS)
    }

    return $ReturnValue
}

function HV-VMVFConfigInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMVFOSConfig,

        [string]$VMSwitchType = "Internal"
    )

    $LocationInfo.VM.Number = $null
    $LocationInfo.VF.Number = $null
    $LocationInfo.VM.OS = $null
    $LocationInfo.VM.CPU = 0
    $LocationInfo.VM.Memory = $null
    $LocationInfo.VM.HyperVGeneration = 0
    $LocationInfo.VM.Switch = $null
    $LocationInfo.VM.ImageName = $null
    $LocationInfo.VM.NameArray = [System.Array] @()
    $LocationInfo.VF.PFVFList = [hashtable] @{}

    if ([String]::IsNullOrEmpty($VMVFOSConfig)) {
        Win-DebugTimestamp -output ("Host: The config of 'VMVFOS' is not null for HV mode")
    } else {
        $HostVMs = $VMVFOSConfig.split("_")[0]
        $LocationInfo.VM.Number = [int]($HostVMs.Substring(0, $HostVMs.Length - 2))
        $HostVFs = $VMVFOSConfig.split("_")[1]
        $LocationInfo.VF.Number = [int]($HostVFs.Substring(0, $HostVFs.Length - 2))
        $LocationInfo.VM.OS = ($VMVFOSConfig.split("_")[2]).split(".")[0]
        $LocationInfo.VM.CPU = $LocationInfo.VF.Number
        if ($LocationInfo.VM.CPU -le 16) {$LocationInfo.VM.CPU = 16}
        $LocationInfo.VM.HyperVGeneration = 1

        $LocalMemory = [int]((Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory /1gb)
        $LocalMemoryUse = [Math]::Truncate($LocalMemory * 0.75)
        $VMMemory = [Math]::Truncate($LocalMemoryUse / $LocationInfo.VM.Number)
        if ($VMMemory -gt 32) {$VMMemory = 32}
        $LocationInfo.VM.Memory = "{0}GiB" -f $VMMemory

        $LocationInfo.VM.Switch = HV-VMSwitchCreate -VMSwitchType $VMSwitchType

        if ($LocationInfo.VM.OS -eq "windows2019") {$LocationInfo.VM.ImageName = "windows_server_2019_19624"}
        if ($LocationInfo.VM.OS -eq "windows2022") {$LocationInfo.VM.ImageName = "windows_server_2022_20348"}
        if ($LocationInfo.VM.OS -eq "ubuntu2004") {$LocationInfo.VM.ImageName = "ubuntu_20.04"}

        $VMCountArray = (1..$LocationInfo.VM.Number)
        $VMCountArray | ForEach-Object {
            $LocationInfo.VM.NameArray += "vm{0}" -f $_
        }

        $intPFCount = -1
        $intVFCount = -1
        $StartFlag = $true
        $LocationInfo.VM.NameArray | ForEach-Object {
            $PFVFArray = @()
            $VFCount = 0
            for ($intVF = 0; $intVF -lt $LocationInfo.PF2VF; $intVF++) {
                for ($intPF = 0; $intPF -lt $LocationInfo.PF.Number; $intPF++) {
                    if (($intVF -eq $intVFCount) -and ($intPF -eq $intPFCount)) {
                        $StartFlag = $true
                        continue
                    }

                    if ($StartFlag) {
                        $PFVFArray += [hashtable] @{
                            PF = $intPF
                            VF = $intVF
                        }
                        $VFCount += 1

                        if ($VFCount -eq $LocationInfo.VF.Number) {
                            $StartFlag = $false
                            $intPFCount = $intPF
                            $intVFCount = $intVF
                        }
                    }
                }
            }

            $LocationInfo.VF.PFVFList[$_] = $PFVFArray
        }

        <#
        $LocationInfo.VM.NameArray | ForEach-Object {
            $VMName = $_
            $LocationInfo.VF.PFVFList[$VMName] | ForEach-Object {
                Win-DebugTimestamp -output ("{0}: {1} > {2}" -f $VMName, $_.PF, $_.VF)
            }
        }
        #>

        Win-DebugTimestamp -output ("      VFNumber : {0}" -f $LocationInfo.VF.Number)
        Win-DebugTimestamp -output ("      VMNumber : {0}" -f $LocationInfo.VM.Number)
        Win-DebugTimestamp -output ("          VMOS : {0}" -f $LocationInfo.VM.OS)
        Win-DebugTimestamp -output ("   VMImageName : {0}" -f $LocationInfo.VM.ImageName)
        Win-DebugTimestamp -output ("      VMSwitch : {0}" -f $LocationInfo.VM.Switch)
        Win-DebugTimestamp -output ("      VMMemory : {0}" -f $LocationInfo.VM.Memory)
        Win-DebugTimestamp -output ("         VMCPU : {0}" -f $LocationInfo.VM.CPU)
    }
}

# About VM
function HV-GetVMIPAddress
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName
    )

    $ReturnValue = $null

    $IPAddressArray = Get-VMNetworkAdapter -VMName $VMName
    if ([String]::IsNullOrEmpty($IPAddressArray)) {
        throw ("Can not get IP address > {0}" -f $VMName)
    } else {
        $ReturnValue = $IPAddressArray.IPAddresses[0]
    }

    return $ReturnValue
}

function HV-WaitVMToCompleted
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName,

        [string]$VMState = "start",

        [bool]$Wait = $true
    )

    $StopFlag = $true
    $TimeoutFlag = $false
    $TimeInterval = 5
    $SleepTime = 0
    $Time = 1000

    if ($VMState -eq "start") {
        $VMStateFlag = "Running"
    }

    if ($VMState -eq "stop") {
        $VMStateFlag = "Off"
    }

    do {
        Start-Sleep -Seconds $TimeInterval
        $SleepTime += $TimeInterval

        if ($SleepTime -ge $Time) {
            $TimeoutFlag = $true
            $StopFlag = $false
        } else {
             if ((get-vm -name $VMName).State -eq $VMStateFlag) {
                 $StopFlag = $false
             }
        }
    } while ($StopFlag)

    if ($TimeoutFlag) {
        Win-DebugTimestamp -output ("{0} VM '{1}' is false > timeout" -f $VMState, $VMName)
        return $false
    }

    if ($Wait) {
        Start-Sleep -Seconds 60
    }

    return $true
}

function HV-RestartVMHard
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName,

        [bool]$StopFlag = $true,

        [bool]$TurnOff = $true,

        [bool]$StartFlag = $true,

        [bool]$WaitFlag = $true
    )

    if ($StopFlag) {
        Win-DebugTimestamp -output ("Stop VM > {0}" -f $VMName)

        if ($TurnOff) {
            Stop-VM -Name $VMName -Force -TurnOff -Confirm:$false -ErrorAction stop | out-null
        } else {
            Stop-VM -Name $VMName -Force -Confirm:$false -ErrorAction stop | out-null
        }
    }

    if ($WaitFlag -and $StopFlag) {
        Start-Sleep -Seconds 30
    }

    if ($StartFlag) {
        Win-DebugTimestamp -output ("Start VM > {0}" -f $VMName)

        Start-VM -Name $VMName -Confirm:$false -ErrorAction stop | out-null
    }

    if ($WaitFlag -and $StartFlag) {
        Start-Sleep -Seconds 30
    }
}

function HV-RestartVMSoft
{
    Param(
        [Parameter(Mandatory=$True)]
        [object]$Session
    )

    Win-DebugTimestamp -output ("{0}: Restart the VM" -f $Session.Name)

    Invoke-Command -Session $Session -ScriptBlock {
        shutdown -r -t 0
    } | out-null
}

function HV-CreateVM
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [Parameter(Mandatory=$True)]
        [string]$VHDPath
    )

    $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
    $ParentsVM = "{0}\{1}.vhdx" -f $VHDPath, $LocationInfo.VM.ImageName
    $ChildVHDPath = "{0}\WTWChildVhds" -f $VHDPath
    $ChildVM = "{0}\{1}.vhdx" -f $ChildVHDPath, $VMName
    if (-not (Test-Path -Path $ChildVHDPath)) {
        New-Item -Path $ChildVHDPath -ItemType Directory | out-null
    }

    if (Test-Path -Path $ChildVM) {
        Get-Item -Path $ChildVM | Remove-Item -Recurse -Force | out-null
    }

    Win-DebugTimestamp -output ("Create new VM named {0}" -f $VMName)

    try {
        Win-DebugTimestamp -output (
            "Create child VHD {0} from parent VHD {1}" -f $ChildVM, $ParentsVM
        )

        New-VHD `
            -ParentPath $ParentsVM `
            -Path $ChildVM `
            -Differencing `
            -ErrorAction Stop | out-null

        $VMMemory = HVConvertIecUnitToLong -IecValue $LocationInfo.VM.Memory

        Win-DebugTimestamp -output (
            "Create new VM instance {0}, {1}, generation {2}" -f
                $VMName,
                $VMMemory,
                $LocationInfo.VM.HyperVGeneration
        )

        New-VM `
            -Name $VMName `
            -MemoryStartupBytes $VMMemory `
            -VHDPath $ChildVM `
            -Generation $LocationInfo.VM.HyperVGeneration `
            -SwitchName $LocationInfo.VM.Switch | out-null

        Set-VM `
            -Name $VMName `
            -ProcessorCount $LocationInfo.VM.CPU `
            -AutomaticStopAction TurnOff `
            -ErrorAction Stop | out-null

        Set-VMProcessor `
            -VMName $VMName `
            -CompatibilityForMigrationEnabled $false `
            -CompatibilityForOlderOperatingSystemsEnabled $false | out-null

        $VMDvd = Get-VMDvdDrive -VMName $VMName
        Remove-VMDvdDrive `
            -VMName $VMName `
            -ControllerNumber $VMDvd.ControllerNumber `
            -ControllerLocation $VMDvd.ControllerLocation | out-null

        if ($LocationInfo.VM.HyperVGeneration -eq 2) {
            Set-VMFirmware `
                -Name $VMName `
                -EnableSecureBoot Off `
                -ErrorAction Stop | out-null
        }

        HV-AssignableDeviceAdd `
            -VMName $VMName `
            -PFVFArray $LocationInfo.VF.PFVFList[$VMNameSuffix] | out-null
        $CheckResult = HV-AssignableDeviceCheck `
            -VMName $VMName `
            -PFVFArray $LocationInfo.VF.PFVFList[$VMNameSuffix]
        if (-not $CheckResult) {
            throw ("Double check device number is failed")
        }
    } catch {
        Win-DebugTimestamp -output ("Caught error > {0}" -f $_)
    }
}

function HV-RemoveVM
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName,

        [string]$VHDPath = $null
    )

    if ([String]::IsNullOrEmpty($VHDPath)) {
        $VHDPath = $VHDAndTestFiles.ParentsVMPath
    }

    $ChildVMPath = "{0}\WTWChildVhds" -f $VHDPath

    if (Test-Path -Path $ChildVMPath) {
        $GetVMError = $null
        $VM = Get-VM `
            -Name $VMName `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetVMError
        if ([String]::IsNullOrEmpty($GetVMError)) {
            Foreach ($HardDrivesPath in $VM.HardDrives.Path) {
                if ($HardDrivesPath -match "WTWChildVhds") {
                    if ($VM.State -ne "off") {
                        HV-RestartVMHard `
                            -VMName $VMName `
                            -StopFlag $true `
                            -TurnOff $true `
                            -StartFlag $false `
                            -WaitFlag $false
                    }

                    $GetVMError = $null
                    $VM = Get-VM `
                        -Name $VMName `
                        -ErrorAction SilentlyContinue `
                        -ErrorVariable GetVMError
                    if ([String]::IsNullOrEmpty($GetVMError)) {
                        Win-DebugTimestamp -output ("Remove VM > {0}" -f $VMName)
                        Remove-VM -Name $VMName -Force -Confirm:$false | out-null
                    }

                    if (Test-Path -Path $HardDrivesPath) {
                        Win-DebugTimestamp -output (
                            "Remove vhdx file > {0}" -f $HardDrivesPath
                        )
                        Remove-Item -Path $HardDrivesPath -Force -Confirm:$false | out-null
                    }

                    $VMPath = "{0}\\{1}" -f $ChildVMPath, $VMName
                    if (Test-Path -Path $VMPath) {
                        Win-DebugTimestamp -output (
                            "Remove directory > {0}" -f $VMPath
                        )
                        Remove-Item -Path $VMPath -Recurse -Force -Confirm:$false | out-null
                    }
                }
            }
        } else {
            $VMArray = Get-ChildItem -Path $ChildVMPath
            if (-not ([String]::IsNullOrEmpty($VMArray))) {
                $VMArray | ForEach-Object {
                    if ($_.Name -match $VMName) {
                        $VMFullPath = "{0}\\{1}" -f $ChildVMPath, $_.Name
                        Remove-Item -Path $VMFullPath -Recurse -Force -Confirm:$false | out-null
                    }
                }
            }
        }
    }
}

# About VM switch
function HV-VMSwitchCreate
{
    Param(
        [string]$VMSwitchType = "Internal"
    )

    $ReturnValue = $STVNetNat.SwitchInternal

    if ($VMSwitchType -eq "Internal") {
        $GetVMSwitchError = $null
        $VMSwitch = Get-VMSwitch `
            -Name $STVNetNat.SwitchInternal `
            -SwitchType $VMSwitchType `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetVMSwitchError

        if ([String]::IsNullOrEmpty($GetVMSwitchError)) {
            $InterfaceIndex = Get-NetAdapter | ForEach-Object {
                if ($_.Name -match $VMSwitchType) {return $_.ifIndex}
            }

            $NetIPAddress = Get-NetIPAddress `
                -InterfaceIndex $InterfaceIndex `
                -AddressFamily IPv4

            $NetIPAddress = $NetIPAddress.IPAddress
            if ($NetIPAddress -ne $STVNetNat.HostIP) {
                Remove-NetIPAddress `
                    -InterfaceIndex $InterfaceIndex `
                    -Confirm:$false `
                    -ErrorAction Stop | Out-Null

                Remove-NetRoute `
                    -InterfaceIndex $InterfaceIndex `
                    -Confirm:$false `
                    -ErrorAction Stop | Out-Null

                New-NetIPAddress `
                    -InterfaceIndex $InterfaceIndex `
                    -IPAddress $STVNetNat.HostIP `
                    -AddressFamily IPv4 `
                    -PrefixLength 24 `
                    -DefaultGateway $STVNetNat.GateWay `
                    -Confirm:$false `
                    -ErrorAction Stop | Out-Null
            }

            Win-DebugTimestamp -output ("Host: Get VM switch(Internal) named {0}" -f $STVNetNat.SwitchInternal)
            $ReturnValue = $STVNetNat.SwitchInternal
        } else {
            New-VMSwitch `
                -Name $STVNetNat.SwitchInternal `
                -SwitchType $VMSwitchType `
                -Confirm:$false `
                -ErrorAction Stop | Out-Null

            $InterfaceIndex = Get-NetAdapter | ForEach-Object {
                if ($_.Name -match $VMSwitchType) {return $_.ifIndex}
            }

            New-NetIPAddress `
                -InterfaceIndex $InterfaceIndex `
                -IPAddress $STVNetNat.HostIP `
                -AddressFamily IPv4 `
                -PrefixLength 24 `
                -DefaultGateway $STVNetNat.GateWay `
                -Confirm:$false `
                -ErrorAction Stop | Out-Null

            Win-DebugTimestamp -output ("Host: Create VM switch(Internal) named {0}" -f $STVNetNat.SwitchInternal)
            $ReturnValue = $STVNetNat.SwitchInternal
        }
    }

    if ($VMSwitchType -eq "External") {
        HV-VMSwitchRemove -VMSwitchType "Internal" | Out-Null

        $GetVMSwitchError = $null
        $VMSwitch = Get-VMSwitch `
            -Name $STVNetNat.SwitchExternal `
            -SwitchType $VMSwitchType `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetVMSwitchError

        if ([String]::IsNullOrEmpty($GetVMSwitchError)) {
            Win-DebugTimestamp -output ("Host: Get VM switch(External) named {0}" -f $STVNetNat.SwitchExternal)
        } else {
            $HostNetwork =  Get-NetIPAddress | Where-Object {
                $_.AddressFamily -eq "IPv4" -and $_.IPAddress -ne "127.0.0.1" -and $_.InterfaceAlias -notmatch "vEthernet"
            }

            if ($HostNetwork.length -ge 1) {
                $VMSwitchList = Get-VMSwitch -SwitchType $VMSwitchType
                if ($VMSwitchList.length -ge 1) {
                    Win-DebugTimestamp -output ("Host: Rename VM switch(External) to {0}" -f $STVNetNat.SwitchExternal)
                    try {
                        Rename-VMSwitch `
                            -VMSwitch $VMSwitchList[0] `
                            -NewName $STVNetNat.SwitchExternal `
                            -Confirm:$false `
                            -ErrorAction Stop | Out-Null
                    } catch {
                        throw ("Error: Rename VM switch(External) > {0}" -f $STVNetNat.SwitchExternal)
                    }
                } else {
                    Win-DebugTimestamp -output ("Host: Create VM switch(External) named {0}" -f $STVNetNat.SwitchExternal)
                    $HostNetwork = $HostNetwork[0]
                    $HostAdapter = Get-NetAdapter -Name $HostNetwork.InterfaceAlias

                    try {
                        New-VMSwitch `
                            -Name $STVNetNat.SwitchExternal `
                            -NetAdapterInterfaceDescription $HostAdapter.InterfaceDescription `
                            -Confirm:$false `
                            -ErrorAction Stop | Out-Null
                    } catch {
                        throw ("Error: Create VM switch(External) > {0}" -f $STVNetNat.SwitchExternal)
                    }
                }
            } else {
                throw ("Error: Can not create VM switch, because no network on host")
            }
        }

        $ReturnValue = $STVNetNat.SwitchExternal
    }

    return $ReturnValue
}

function HV-VMSwitchRemove
{
    Param(
        [string]$VMSwitchType = "Internal"
    )

    $GetVMSwitchError = $null
    $VMSwitchArray = Get-VMSwitch `
        -SwitchType $VMSwitchType `
        -ErrorAction SilentlyContinue `
        -ErrorVariable GetVMSwitchError

    if ([String]::IsNullOrEmpty($GetVMSwitchError)) {
        Win-DebugTimestamp -output ("Host: Remove VM switch type: {0}" -f $VMSwitchType)
        Get-VMSwitch -SwitchType $VMSwitchType | Remove-VMSwitch -Force -Confirm:$false | Out-Null
    }
}

# About VF
function HV-AssignableDeviceAdd
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName,

        [Parameter(Mandatory=$True)]
        [array]$PFVFArray
    )

    HV-AssignableDeviceRemove -VMName $VMName | out-null

    $PFVFArray | ForEach-Object {
        ForEach ($localPath in $LocationInfo.PF.PCI) {
            if ([int]($localPath.Id) -eq [int]($_.PF)) {
                Win-DebugTimestamp -output (
                    "Adding QAT VF with InstancePath {0} and VF# {1}" -f
                        $localPath.Instance, $_.VF
                )

                try {
                    Add-VMAssignableDevice `
                        -VMName $VMName `
                        -LocationPath $localPath.Instance `
                        -VirtualFunction $_.VF | out-null
                } catch {
                    throw ("Error: Assigning qat device > {0}" -f $localPath.Instance)
                }
            }
        }
    }
}

function HV-AssignableDeviceRemove
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName
    )

    Remove-VMAssignableDevice -Verbose -VMName $VMName | out-null
}

function HV-AssignableDeviceCheck
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMName,

        [Parameter(Mandatory=$True)]
        [array]$PFVFArray
    )

    $ReturnValue = $true

    $TargetDevNumber = $PFVFArray.Length
    $CheckDevNumber = (Get-VMAssignableDevice -VMName $VMName).Length
    if ($TargetDevNumber -eq $CheckDevNumber) {
        Win-DebugTimestamp -output ("Double check assignable VF number is correct")
        $ReturnValue = $true
    } else {
        Win-DebugTimestamp -output ("Double check assignable VF number is incorrect")
        $ReturnValue = $false
    }

    return $ReturnValue
}


Export-ModuleMember -Function *-*
