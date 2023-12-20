
function Domain-PSSessionCreate
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$RMName,

        [Parameter(Mandatory=$True)]
        [string]$PSName,

        [bool]$IsWin = $true
    )

    $RMNameReal = "{0}.{1}.cc" -f $RMName, $DomainName

    $PSSessionStatus = Domain-PSSessionCheck -RMName $RMName -PSName $PSName
    if (-not $PSSessionStatus.result) {
        if ($PSSessionStatus.exist) {
            Domain-PSSessionRemove -PSName $PSName | out-null
        }

        Win-DebugTimestamp -output ("Create PS session named {0} for remote machine named {1}" -f $PSName, $RMName)

        for ($i = 1; $i -lt 50; $i++) {
            try {
                $PSSessionError = $null
                New-PSSession `
                    -ComputerName $RMNameReal `
                    -Credential $DomainCredentials `
                    -Name $PSName `
                    -ErrorAction SilentlyContinue `
                    -ErrorVariable ProcessError | out-null

                Start-Sleep -Seconds 5

                $PSSessionStatus = Domain-PSSessionCheck -RMName $RMName -PSName $PSName
                if ($PSSessionStatus.result) {
                    Win-DebugTimestamp -output ("Creating PS seesion is successful > {0}" -f $PSName)
                    break
                }
            } catch {
                Win-DebugTimestamp -output ("Creating PS seesion is failed and try again > {0}" -f $i)
                continue
            }
        }

        $Session = Get-PSSession -name $PSName
        Invoke-Command -Session $Session -ScriptBlock {
            $ModuleStatus = Get-Module -Name "WinBase"
            if ([String]::IsNullOrEmpty($ModuleStatus)) {
                Import-Module "C:\QatTestBerta\lib\WinBase.psm1" -Force -DisableNameChecking
            }

            Set-Location "C:\QatTestBerta"
        }
    }

    return (Get-PSSession -name $PSName)
}

function Domain-PSSessionRemove
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

function Domain-PSSessionCheck
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$RMName,

        [Parameter(Mandatory=$True)]
        [string]$PSName
    )

    $ReturnValue = [hashtable] @{
        result = $false
        exist = $false
    }

    $RMNameReal = "{0}.{1}.cc" -f $RMName, $DomainName

    $PSSessionError = $null
    $PSSession = Get-PSSession `
        -Name $PSName `
        -ErrorAction SilentlyContinue `
        -ErrorVariable ProcessError

    if ([String]::IsNullOrEmpty($PSSessionError)) {
        if ($PSSession.ComputerName -eq $RMNameReal) {
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

function Domain-RemoteInfoInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [hashtable]$BertaConfig,

        [Parameter(Mandatory=$True)]
        [string]$BuildPath,

        [bool]$UseS2D = $false
    )

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSessionName

    Win-DebugTimestamp -output ("Init test ENV on target server....")
    Domain-RemoveVMs -Remote $true -UseS2D $UseS2D | out-null

    if ($UseS2D) {
        $VHDPath = $LocationInfo.Domain.S2DStorage
    } else {
        $VHDPath = $VHDAndTestFiles.ParentsVMPath
    }

    $ScriptBlock = {
        Param($VHDPath, $SetPathFlag)
        Enable-VMMigration

        $ServerIP = Get-NetIPAddress -AddressFamily IPv4 -IPAddress 10.67.*
        Remove-VMMigrationNetwork *
        Add-VMMigrationNetwork $ServerIP.IPAddress

        if ($SetPathFlag) {
            if (Test-Path -Path $VHDPath) {
                $ChildVHDPath = "{0}\WTWChildVhds" -f $VHDPath
            } else {
                $ChildVHDPath = "C:\vhd\WTWChildVhds"
            }

            if (-not (Test-Path -Path $ChildVHDPath)) {
                New-Item -Path $ChildVHDPath -ItemType Directory | out-null
            }

            Set-VMHost `
                -UseAnyNetworkForMigration $false `
                -VirtualMachineMigrationAuthenticationType "Kerberos" `
                -VirtualMachineMigrationPerformanceOption "Compression" `
                -VirtualHardDiskPath $ChildVHDPath `
                -VirtualMachinePath $ChildVHDPath
        } else {
            Set-VMHost `
                -UseAnyNetworkForMigration $false `
                -VirtualMachineMigrationAuthenticationType "Kerberos" `
                -VirtualMachineMigrationPerformanceOption "Compression"
        }
    }

    Invoke-Command `
        -ScriptBlock $ScriptBlock `
        -ArgumentList $VHDPath, $true | out-null
    Invoke-Command `
        -Session $DomainPSSession `
        -ScriptBlock $ScriptBlock `
        -ArgumentList $VHDPath, $false | out-null

    Win-DebugTimestamp -output ("{0}: Init test script ...." -f $LocationInfo.Domain.TargetServer)
    Invoke-Command -Session $DomainPSSession -ScriptBlock {
        # CD C:\
        # Berta-ENVInit | out-null
        # Berta-CopyTestDir | out-null
    } | out-null

    $DomainDriverPath = $LocationInfo.Domain.DriverPath
    $DomainResultPath = $LocationInfo.Domain.ResultPath
    WBase-ClearDir `
        -Remote $true `
        -Path $DomainDriverPath `
        -Session $DomainPSSession | out-null
    WBase-ClearDir `
        -Remote $true `
        -Path $DomainResultPath `
        -Session $DomainPSSession | out-null
    WBase-CopyDir `
        -Remote $true `
        -Path $BuildPath `
        -Destination $DomainDriverPath `
        -Session $DomainPSSession | out-null

    WBase-ClearDir `
        -Remote $false `
        -Path $DomainDriverPath | out-null
    WBase-ClearDir `
        -Remote $false `
        -Path $DomainResultPath | out-null
    WBase-CopyDir `
        -Remote $false `
        -Path $BuildPath `
        -Destination $DomainDriverPath | out-null

    Win-DebugTimestamp -output ("{0}: Init base info ...." -f $LocationInfo.Domain.TargetServer)
    $DomainRemoteInfo = Invoke-Command -Session $DomainPSSession -ScriptBlock {
        Param($DomainDriverPath, $DomainResultPath, $BertaConfig, $TargetServer)
        $LocationInfo.HVMode = $true
        $LocationInfo.IsWin = $true
        $LocationInfo.VM.IsWin = $true
        $LocationInfo.WriteLogToConsole = $false
        $LocationInfo.WriteLogToFile = $true
        $BertaConfig["TargetServer"] = $TargetServer

        WBase-ReturnFilesInit `
            -BertaResultPath $DomainResultPath `
            -ResultFile "result.log" | out-null
        $PFVFDriverPath = WBase-GetDriverPath -BuildPath $DomainDriverPath

        WBase-LocationInfoInit -BertaResultPath $DomainResultPath `
                               -QatDriverFullPath $PFVFDriverPath `
                               -BertaConfig $BertaConfig | out-null

        return $LocationInfo
    } -ArgumentList $DomainDriverPath, $DomainResultPath, $BertaConfig, $env:COMPUTERNAME

    Win-DebugTimestamp -output ("The info of {0}" -f $LocationInfo.Domain.TargetServer)
    Win-DebugTimestamp -output ("              HVMode : {0}" -f $DomainRemoteInfo.HVMode)
    Win-DebugTimestamp -output ("              UQMode : {0}" -f $DomainRemoteInfo.UQMode)
    Win-DebugTimestamp -output ("            TestMode : {0}" -f $DomainRemoteInfo.TestMode)
    Win-DebugTimestamp -output ("           DebugMode : {0}" -f $DomainRemoteInfo.DebugMode)
    Win-DebugTimestamp -output ("        VerifierMode : {0}" -f $DomainRemoteInfo.VerifierMode)
    Win-DebugTimestamp -output ("             QatType : {0}" -f $DomainRemoteInfo.QatType)
    Win-DebugTimestamp -output ("        FriendlyName : {0}" -f $DomainRemoteInfo.FriendlyName)
    Win-DebugTimestamp -output ("              Socket : {0}" -f $DomainRemoteInfo.Socket)
    Win-DebugTimestamp -output ("           Socket2PF : {0}" -f $DomainRemoteInfo.Socket2PF)
    Win-DebugTimestamp -output ("               PF2VF : {0}" -f $DomainRemoteInfo.PF2VF)
    Win-DebugTimestamp -output ("            PFNumber : {0}" -f $DomainRemoteInfo.PF.Number)
    Win-DebugTimestamp -output ("                 PFs : {0}" -f $DomainRemoteInfo.PF.PCI)
    Win-DebugTimestamp -output ("     BertaResultPath : {0}" -f $DomainRemoteInfo.BertaResultPath)
    Win-DebugTimestamp -output ("     PFQatDriverPath : {0}" -f $DomainRemoteInfo.PF.DriverPath)
    Win-DebugTimestamp -output ("     PFQatDriverName : {0}" -f $DomainRemoteInfo.PF.DriverName)
    Win-DebugTimestamp -output ("      PFQatDriverExe : {0}" -f $DomainRemoteInfo.PF.DriverExe)
    Win-DebugTimestamp -output ("     VFQatDriverPath : {0}" -f $DomainRemoteInfo.VF.DriverPath)
    Win-DebugTimestamp -output ("     VFQatDriverName : {0}" -f $DomainRemoteInfo.VF.DriverName)
    Win-DebugTimestamp -output ("          IcpQatName : {0}" -f $DomainRemoteInfo.IcpQatName)
    Win-DebugTimestamp -output ("     ExecutingServer : {0}" -f $DomainRemoteInfo.Domain.ExecutingServer)
    Win-DebugTimestamp -output ("        TargetServer : {0}" -f $DomainRemoteInfo.Domain.TargetServer)

    return $DomainRemoteInfo
}

function Domain-RemoteVMVFConfigInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [hashtable]$RemoteInfo,

        [Parameter(Mandatory=$True)]
        [string]$VMVFOSConfig,

        [bool]$UseS2D = $false
    )

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSessionName

    Domain-RemoveVMs -Remote $true -UseS2D $UseS2D | out-null

    Win-DebugTimestamp -output ("{0}: Init config info for VMVFOS...." -f $LocationInfo.Domain.TargetServer)
    $ReturnValue = Invoke-Command -Session $DomainPSSession -ScriptBlock {
        Param($RemoteInfo, $VMVFOSConfig, $VMSwitchType)
        $LocationInfo = $RemoteInfo
        HV-VMVFConfigInit `
            -VMVFOSConfig $VMVFOSConfig `
            -VMSwitchType $VMSwitchType | out-null
        return $LocationInfo
    } -ArgumentList $RemoteInfo, $VMVFOSConfig, "External"

    return $ReturnValue
}

function Domain-RemoveVMs
{
    Param(
        [bool]$Local = $false,

        [bool]$Remote = $false,

        [bool]$UseS2D = $false
    )

    if ($UseS2D) {
        $VHDPath = $LocationInfo.Domain.S2DStorage
    } else {
        $VHDPath = $VHDAndTestFiles.ParentsVMPath
    }

    if ($Remote) {
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSessionName

        if ($UseS2D) {
            $VMArray = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                $VMArray = @()
                $VMList = Get-VM
                if (-not [String]::IsNullOrEmpty($VMList)) {
                    Foreach ($VM in $VMList) {
                        if ($VM.State -ne "off") {
                            HV-RestartVMHard `
                                -VMName $VM.Name `
                                -StopFlag $true `
                                -TurnOff $true `
                                -StartFlag $false `
                                -WaitFlag $false
                        }

                        Remove-VM -Name $VM.Name -Force -Confirm:$false | out-null
                        if ($VM.HardDrives.Path -match "QatServer305") {
                            $VMArray += $VM.HardDrives.Path
                        } else {
                            Remove-Item -Path $VM.HardDrives.Path -Force -Confirm:$false | out-null
                        }
                    }
                }
                return $VMArray
            }

            Foreach ($VMParh in $VMArray) {
                Remove-Item -Path $VMParh -Force -Confirm:$false | out-null
            }
        } else {
            Invoke-Command -Session $DomainPSSession -ScriptBlock {
                Param($VHDPath)
                $VMList = Get-VM
                if (-not [String]::IsNullOrEmpty($VMList)) {
                    Foreach ($VM in $VMList) {
                        HV-RemoveVM -VMName $VM.Name -VHDPath $VHDPath | out-null
                    }
                }
            } -ArgumentList $VHDPath | out-null
        }
    }

    if ($Local) {
        Invoke-Command -ScriptBlock {
            Param($VHDPath)
            $VMList = Get-VM
            if (-not [String]::IsNullOrEmpty($VMList)) {
                Foreach ($VM in $VMList) {
                    HV-RemoveVM -VMName $VM.Name -VHDPath $VHDPath | out-null
                }
            }
        } -ArgumentList $VHDPath | out-null
    }
}

function Domain-CheckVM
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$VMNameList
    )

    $ReturnValue = [hashtable] @{
        local = $false
        remote = $false
    }

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSessionName

    $ScriptBlock = {
        Param($VMNameList)
        $ReturnValue = $true

        $VMNameList | ForEach-Object {
            $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $_
            $GetVMError = $null
            $VM = Get-VM `
                -Name $VMName `
                -ErrorAction SilentlyContinue `
                -ErrorVariable GetVMError

            if (-not [String]::IsNullOrEmpty($GetVMError)) {
                $ReturnValue = $false
            }
        }

        return $ReturnValue
    }

    $ReturnValue.local = Invoke-Command `
        -ScriptBlock $ScriptBlock `
        -ArgumentList $VMNameList

    $ReturnValue.remote = Invoke-Command `
        -Session $DomainPSSession `
        -ScriptBlock $ScriptBlock `
        -ArgumentList $VMNameList

    return $ReturnValue
}

function Domain-MoveVM
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$VMNameList,

        [Parameter(Mandatory=$True)]
        [bool]$isDomain,

        [bool]$UseS2D = $false
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $ScriptBlock = {
        Param($VMNameList, $UseS2D)
        $ReturnValue = [hashtable] @{
            result = $true
            error = "no_error"
        }

        WBase-GetInfoFile | out-null

        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSessionName

        $RMName = "{0}.{1}.cc" -f $LocationInfo.Domain.TargetServer, $DomainName
        $VMNameList | ForEach-Object {
            $PSSessionName = "Session_{0}" -f $_
            $VMName = "{0}_{1}" -f $LocationInfo.Domain.ExecutingServer, $_
            $NewVMName = "{0}_{1}" -f $LocationInfo.Domain.TargetServer, $_

            # Remove all VFs
            Win-DebugTimestamp -output ("{0}: Remove all VFs ...." -f $PSSessionName)
            HV-AssignableDeviceRemove -VMName $VMName | out-null

            # Move VM
            Win-DebugTimestamp -output ("{0}: Start to move vm ...." -f $PSSessionName)
            if ($UseS2D) {
                Move-VM `
                    -Name $VMName `
                    -DestinationHost $RMName | out-null
            } else {
                $DestinationStoragePath = "{0}\\{1}_{2}" -f
                    $VHDAndTestFiles.ChildVMPath,
                    $LocationInfo.Domain.TargetServer,
                    $_

                Invoke-Command -Session $DomainPSSession -ScriptBlock {
                    Param($DestinationStoragePath)
                    if (Test-Path -Path $DestinationStoragePath) {
                        Remove-Item -Path $DestinationStoragePath -Recurse -Force -Confirm:$false | out-null
                    }
                } -ArgumentList $DestinationStoragePath | out-null

                Move-VM `
                    -Name $VMName `
                    -IncludeStorage `
                    -DestinationStoragePath $DestinationStoragePath `
                    -DestinationHost $RMName | out-null
            }
            Win-DebugTimestamp -output ("{0}: Move vm ... Completed" -f $PSSessionName)

            # Double check VM exist on ExecutingServer
            Win-DebugTimestamp -output (
                "{0}: Double check all VM on {1} ..." -f
                    $PSSessionName,
                    $LocationInfo.Domain.ExecutingServer
            )
            $GetVMError = $null
            $VM = Get-VM `
                -Name $VMName `
                -ErrorAction SilentlyContinue `
                -ErrorVariable GetVMError
            if ([String]::IsNullOrEmpty($GetVMError)) {
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "no_Executing_VM"
                }

                Win-DebugTimestamp -output (
                    "{0}: Double check all VM on {1} ... false > {2}" -f
                        $PSSessionName,
                        $LocationInfo.Domain.ExecutingServer,
                        $ReturnValue.error
                )
            } else {
                Win-DebugTimestamp -output (
                    "{0}: Double check all VM on {1} ... true" -f
                        $PSSessionName,
                        $LocationInfo.Domain.ExecutingServer
                )
            }

            # Double check VM exist on TargetServer
            if ($ReturnValue.result) {
                Win-DebugTimestamp -output (
                    "{0}: Double check all VM on {1}" -f
                        $PSSessionName,
                        $LocationInfo.Domain.TargetServer
                )

                $ReturnValue = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                    Param($VMName, $NewVMName)
                    $ReturnValue = [hashtable] @{
                        result = $true
                        error = "no_error"
                    }

                    $GetVMError = $null
                    $VM = Get-VM `
                        -Name $VMName `
                        -ErrorAction SilentlyContinue `
                        -ErrorVariable GetVMError

                    if ([String]::IsNullOrEmpty($GetVMError)) {
                        Rename-VM -Name $VMName -NewName $NewVMName | out-null
                    } else {
                        $ReturnValue.result = $false
                        $ReturnValue.error = "no_target_VM"
                    }

                    return $ReturnValue
                } -ArgumentList $VMName, $NewVMName

                if ($ReturnValue.result) {
                    Win-DebugTimestamp -output (
                        "{0}: Double check all VM on {1} ... true" -f
                            $PSSessionName,
                            $LocationInfo.Domain.TargetServer
                    )
                } else {
                    Win-DebugTimestamp -output (
                        "{0}: Double check all VM on {1} ... false > {2}" -f
                            $PSSessionName,
                            $LocationInfo.Domain.TargetServer,
                            $ReturnValue.error
                    )
                }
            }

            # reAdd VFs for VMs on the target machine
            if ($ReturnValue.result) {
                Win-DebugTimestamp -output (
                    "{0}: reAdd VFs on {1}" -f
                        $PSSessionName,
                        $LocationInfo.Domain.TargetServer
                )

                $ReturnValue = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                    Param($VMName, $VMNameSuffix)
                    $ReturnValue = [hashtable] @{
                        result = $true
                        error = "no_error"
                    }

                    HV-AssignableDeviceAdd `
                        -VMName $VMName `
                        -PFVFArray $LocationInfo.VF.PFVFList[$VMNameSuffix] | out-null

                    $CheckResult = HV-AssignableDeviceCheck `
                        -VMName $VMName `
                        -PFVFArray $LocationInfo.VF.PFVFList[$VMNameSuffix]
                    if (-not $CheckResult) {
                        $ReturnValue.result = $false
                        $ReturnValue.error = "reAdd_device_fail"
                    }

                    return $ReturnValue
                } -ArgumentList $NewVMName, $_

                if ($ReturnValue.result) {
                    Win-DebugTimestamp -output (
                        "{0}: reAdd VFs on {1} ... true" -f
                            $PSSessionName,
                            $LocationInfo.Domain.TargetServer
                    )
                } else {
                    Win-DebugTimestamp -output (
                        "{0}: reAdd VFs on {1} ... false > {2}" -f
                            $PSSessionName,
                            $LocationInfo.Domain.TargetServer,
                            $ReturnValue.error
                    )
                }
            }

            if ($ReturnValue.result) {
                Win-DebugTimestamp -output ("{0}: Move vm is successful" -f $PSSessionName)
            } else {
                Win-DebugTimestamp -output ("{0}: Move vm is unsuccessful" -f $PSSessionName)
            }

            return $ReturnValue
        }
    }

    if ($isDomain) {
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSessionName

        $ReturnValue = Invoke-Command `
            -Session $DomainPSSession `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $VMNameList, $UseS2D
    } else {
        $ReturnValue = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $VMNameList, $UseS2D
    }

    return $ReturnValue
}

function Domain-ProcessParcomp
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [Parameter(Mandatory=$True)]
        [string]$CompressType = "Compress",

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$Chunk = 64,

        [int]$blockSize = 4096,

        [int]$numThreads = 6,

        [int]$numIterations = 200,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    WBase-GetInfoFile | out-null
    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    $RemoteInfo = WBase-ReadHashtableFromJsonFile -InfoFilePath $RemoteInfoFilePath
    $RemoteInfo.WriteLogToConsole = $false
    $RemoteInfo.WriteLogToFile = $false

    $ParcompType = "Fallback"
    $runParcompType = "Process"
    $ParcompTestResultName = "ProcessResult_{0}.json" -f $keyWords
    $ParcompTestResultPath = "{0}\\{1}" -f $LocalProcessPath, $ParcompTestResultName

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSessionName

    $PSSessionName = "Session_{0}" -f $VMNameSuffix
    $VMName = "{0}_{1}" -f $LocationInfo.Domain.ExecutingServer, $VMNameSuffix
    $NewVMName = "{0}_{1}" -f $LocationInfo.Domain.TargetServer, $VMNameSuffix
    $Session = HV-PSSessionCreate `
        -VMName $VMName `
        -PSName $PSSessionName `
        -IsWin $true `
        -CheckFlag $false

    # Run tracelog
    UT-TraceLogStart -Remote $true -Session $Session | out-null

    Win-DebugTimestamp -output (
        "{0}: Start to process of Live Migration test..." -f $PSSessionName
    )

    # Run parcomp test
    $ProcessCount = 0
    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
        $ProcessCount += 1
        $CompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.CompressPathName
        $CompressTestResult = WBase-Parcomp `
            -Remote $true `
            -Session $Session `
            -deCompressFlag $false `
            -CompressProvider $CompressProvider `
            -deCompressProvider $deCompressProvider `
            -QatCompressionType $QatCompressionType `
            -Level $Level `
            -Chunk $Chunk `
            -blockSize $blockSize `
            -numThreads $numThreads `
            -numIterations $numIterations `
            -ParcompType $ParcompType `
            -runParcompType $runParcompType `
            -TestPath $CompressTestPath `
            -TestFileType $TestFileType `
            -TestFileSize $TestFileSize
    }

    if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
        $ProcessCount += 1
        $deCompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.deCompressPathName
        $deCompressTestResult = WBase-Parcomp `
            -Remote $true `
            -Session $Session `
            -deCompressFlag $true `
            -CompressProvider $CompressProvider `
            -deCompressProvider $deCompressProvider `
            -QatCompressionType $QatCompressionType `
            -Level $Level `
            -Chunk $Chunk `
            -blockSize $blockSize `
            -numThreads $numThreads `
            -numIterations $numIterations `
            -ParcompType $ParcompType `
            -runParcompType $runParcompType `
            -TestPath $deCompressTestPath `
            -TestFileType $TestFileType `
            -TestFileSize $TestFileSize
    }

    # Check parcomp test process number
    $CheckProcessNumberFlag = WBase-CheckProcessNumber `
        -ProcessName "parcomp" `
        -ProcessNumber $ProcessCount `
        -Remote $true `
        -Session $Session
    if (-not $CheckProcessNumberFlag.result) {
        $ReturnValue.result = $CheckProcessNumberFlag.result
        $ReturnValue.error = $CheckProcessNumberFlag.error
    }

    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $ParcompTestResultPath | out-null

    # wait operation completed
    $StartOperationFlagName = "{0}_{1}" -f $StartOperationFlag, $keyWords
    $StartOperationFlagPath = "{0}\\{1}" -f $LocalProcessPath, $StartOperationFlagName
    if (-not (Test-Path -Path $StartOperationFlagPath)) {
        New-Item `
            -Path $LocalProcessPath `
            -Name $StartOperationFlagName `
            -ItemType "file" | out-null
    }

    $OperationCompletedFlagArray = @()
    $OperationCompletedFlagArray += $OperationCompletedFlag
    WTW-ChechFlagFile -FlagFileNameArray $OperationCompletedFlagArray | out-null

    # Double check the output log
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: Double check output log on the target machine" -f $DomainPSSession.Name
        )
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSessionName

        $CheckOutputLogStatus = Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param($RemoteInfo, $VMName, $VMNameSuffix, $CompressType)
            $ReturnValue = [hashtable] @{
                result = $true
                error = "no_error"
            }

            $PSSessionName = "Session_{0}" -f $VMNameSuffix
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false

            $global:LocationInfo = $RemoteInfo

            $WaitStatus = WBase-WaitProcessToCompletedByName `
                -ProcessName "parcomp" `
                -Remote $true `
                -Session $Session
            if (-not $WaitStatus.result) {
                $ReturnValue.result = $WaitStatus.result
                $ReturnValue.error = $WaitStatus.error
                return $ReturnValue
            }

            if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                $CompressTestOutLogPath = "{0}\\{1}\\{2}" -f
                    $STVWinPath,
                    $ParcompOpts.CompressPathName,
                    $ParcompOpts.OutputLog
                $CompressTestErrorLogPath = "{0}\\{1}\\{2}" -f
                    $STVWinPath,
                    $ParcompOpts.CompressPathName,
                    $ParcompOpts.ErrorLog
                $CheckOutput = WBase-CheckOutputLog `
                    -TestOutputLog $CompressTestOutLogPath `
                    -TestErrorLog $CompressTestErrorLogPath `
                    -Session $Session `
                    -Remote $true `
                    -keyWords "Mbps"
                if (-not $CheckOutput.result) {
                    $ReturnValue.result = $CheckOutput.result
                    $ReturnValue.error = $CheckOutput.error
                    return $ReturnValue
                }
            }

            if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
                $deCompressTestOutLogPath = "{0}\\{1}\\{2}" -f
                    $STVWinPath,
                    $ParcompOpts.deCompressPathName,
                    $ParcompOpts.OutputLog
                $deCompressTestErrorLogPath = "{0}\\{1}\\{2}" -f
                    $STVWinPath,
                    $ParcompOpts.deCompressPathName,
                    $ParcompOpts.ErrorLog
                $CheckOutput = WBase-CheckOutputLog `
                    -TestOutputLog $deCompressTestOutLogPath `
                    -TestErrorLog $deCompressTestErrorLogPath `
                    -Session $Session `
                    -Remote $true `
                    -keyWords "Mbps"
                if (-not $CheckOutput.result) {
                    $ReturnValue.result = $CheckOutput.result
                    $ReturnValue.error = $CheckOutput.error
                    return $ReturnValue
                }
            }

            return $ReturnValue
        } -ArgumentList $RemoteInfo, $NewVMName, $VMNameSuffix, $CompressType

        if ($CheckOutputLogStatus.result) {
            Win-DebugTimestamp -output (
                "{0}: Double check output log is passed" -f $DomainPSSession.Name
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: Double check output log is failed" -f $DomainPSSession.Name
            )
            $ReturnValue.result = $CheckOutputLogStatus.result
            $ReturnValue.error = $CheckOutputLogStatus.error

            WBase-WriteHashtableToJsonFile `
                -Info $ReturnValue `
                -InfoFilePath $ParcompTestResultPath | out-null
        }
    }

    # Double check the output files
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: Double check the output files on the target machine" -f $DomainPSSession.Name
        )
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSessionName

        $ParcompArgs = [hashtable] @{
            CompressType = $CompressType
            CompressProvider = $CompressProvider
            deCompressProvider = $deCompressProvider
            QatCompressionType = $QatCompressionType
            Level = $Level
            Chunk = $Chunk
            blockSize = $blockSize
            TestFileType = $TestFileType
            TestFileSize = $TestFileSize
        }
        $CheckOutputFileStatus = Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param($RemoteInfo, $VMName, $VMNameSuffix, $ParcompArgs)
            $ReturnValue = [hashtable] @{
                result = $true
                error = "no_error"
            }

            $PSSessionName = "Session_{0}" -f $VMNameSuffix
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false

            $global:LocationInfo = $RemoteInfo

            if (($ParcompArgs.CompressType -eq "Compress") -or
                ($ParcompArgs.CompressType -eq "All")) {
                $CompressTestLogPath = "{0}\\{1}" -f
                    $STVWinPath,
                    $ParcompOpts.CompressPathName
                $CheckMD5Result = WBase-CheckOutputFile `
                    -Remote $true `
                    -Session $Session `
                    -deCompressFlag $false `
                    -CompressProvider $ParcompArgs.CompressProvider `
                    -deCompressProvider $ParcompArgs.deCompressProvider `
                    -QatCompressionType $ParcompArgs.QatCompressionType `
                    -Level $ParcompArgs.Level `
                    -Chunk $ParcompArgs.Chunk `
                    -blockSize $ParcompArgs.blockSize `
                    -TestFileType $ParcompArgs.TestFileType `
                    -TestFileSize $ParcompArgs.TestFileSize `
                    -TestPath $CompressTestLogPath

                if (-not $CheckMD5Result.result) {
                    $ReturnValue.result = $CheckMD5Result.result
                    $ReturnValue.error = $CheckMD5Result.error
                    return $ReturnValue
                }
            }

            if (($ParcompArgs.CompressType -eq "deCompress") -or
                ($ParcompArgs.CompressType -eq "All")) {
                $deCompressTestLogPath = "{0}\\{1}" -f
                    $STVWinPath,
                    $ParcompOpts.deCompressPathName
                $CheckMD5Result = WBase-CheckOutputFile `
                    -Remote $true `
                    -Session $Session `
                    -deCompressFlag $true `
                    -CompressProvider $ParcompArgs.CompressProvider `
                    -deCompressProvider $ParcompArgs.deCompressProvider `
                    -QatCompressionType $ParcompArgs.QatCompressionType `
                    -Level $ParcompArgs.Level `
                    -Chunk $ParcompArgs.Chunk `
                    -blockSize $ParcompArgs.blockSize `
                    -TestFileType $ParcompArgs.TestFileType `
                    -TestFileSize $ParcompArgs.TestFileSize `
                    -TestPath $deCompressTestLogPath

                if (-not $CheckMD5Result.result) {
                    $ReturnValue.result = $CheckMD5Result.result
                    $ReturnValue.error = $CheckMD5Result.error
                    return $ReturnValue
                }
            }

            return $ReturnValue
        } -ArgumentList $RemoteInfo, $NewVMName, $VMNameSuffix, $ParcompArgs

        if ($CheckOutputFileStatus.result) {
            Win-DebugTimestamp -output (
                "{0}: Double check the output files is passed" -f $DomainPSSession.Name
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: Double check the output files is failed" -f $DomainPSSession.Name
            )
            $ReturnValue.result = $CheckOutputFileStatus.result
            $ReturnValue.error = $CheckOutputFileStatus.error

            WBase-WriteHashtableToJsonFile `
                -Info $ReturnValue `
                -InfoFilePath $ParcompTestResultPath | out-null
        }
    }

    # After parcomp fallback test, run simple parcomp test
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: After parcomp fallback test, run simple parcomp test" -f $DomainPSSession.Name
        )
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSessionName

        $SimpleParcompStatus = Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param($RemoteInfo, $VMName, $VMNameSuffix)
            $ReturnValue = [hashtable] @{
                result = $true
                error = "no_error"
            }

            $PSSessionName = "Session_{0}" -f $VMNameSuffix
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false

            $global:LocationInfo = $RemoteInfo

            $ParcompTestResult = WTW-SimpleParcomp -Session $Session
            if (-not $ParcompTestResult.result) {
                $ReturnValue.result = $ParcompTestResult.result
                $ReturnValue.error = $ParcompTestResult.error
            }

            return $ReturnValue
        } -ArgumentList $RemoteInfo, $NewVMName, $VMNameSuffix

        if ($SimpleParcompStatus.result) {
            Win-DebugTimestamp -output (
                "{0}: The simple parcomp test is passed" -f $DomainPSSession.Name
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: The simple parcomp test is failed" -f $DomainPSSession.Name
            )
            $ReturnValue.result = $SimpleParcompStatus.result
            $ReturnValue.error = $SimpleParcompStatus.error

            WBase-WriteHashtableToJsonFile `
                -Info $ReturnValue `
                -InfoFilePath $ParcompTestResultPath | out-null
        }
    }
}

function Domain-LiveMParcomp
{
    Param(
        [Parameter(Mandatory=$True)]
        [hashtable]$RemoteInfo,

        [string]$CompressType = "Compress",

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$blockSize = 4096,

        [int]$Chunk = 64,

        [int]$numThreads = 6,

        [int]$numIterations = 200,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200,

        [string]$TestPath = $null,

        [bool]$UseS2D = $false
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    WBase-GenerateInfoFile | out-null
    WBase-WriteHashtableToJsonFile `
        -Info $RemoteInfo `
        -InfoFilePath $RemoteInfoFilePath | out-null

    $VMNameList = $LocationInfo.VM.NameArray
    $ParcompProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()
    $StartOperationFlagArray = [System.Array] @()

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.PathName
    }

    # Check VM
    Domain-RemoveVMs -Remote $true -UseS2D $UseS2D | out-null

    $isDomain = $false
    $CheckVMs = Domain-CheckVM -VMNameList $VMNameList
    if ($CheckVMs.local) {
        if ($CheckVMs.remote) {
            Domain-RemoveVMs -Remote $true -UseS2D $UseS2D | out-null
        }

        $isDomain = $false
    } else {
        if ($CheckVMs.remote) {
            $isDomain = $true
        } else {
            $VMVFOSConfig = "{0}vm_{1}vf_{2}" -f
                $LocationInfo.VM.Number,
                $LocationInfo.VF.Number,
                $LocationInfo.VM.OS
            if ($UseS2D) {
                WTW-ENVInit `
                    -VMVFOSConfig $VMVFOSConfig `
                    -VHDPath $LocationInfo.Domain.S2DStorage `
                    -VMSwitchType "External" `
                    -InitVM $true | out-null
            } else {
                WTW-ENVInit `
                    -VMVFOSConfig $VMVFOSConfig `
                    -VMSwitchType "External" `
                    -InitVM $true | out-null
            }

            $isDomain = $false
        }
    }

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSessionName

    # Delete Operation Completed Flag file
    $OperationCompletedFlagPath = "{0}\\{1}" -f
        $LocalProcessPath,
        $OperationCompletedFlag
    if (Test-Path -Path $OperationCompletedFlagPath) {
        Get-Item -Path $OperationCompletedFlagPath | Remove-Item -Recurse -Force | out-null
    }

    # Run parcomp test as process
    $VMNameList | ForEach-Object {
        $ParcompProcessArgs = "Domain-ProcessParcomp -VMNameSuffix {0}" -f $_
        $ParcompProcessArgs = "{0} -CompressType {1}" -f $ParcompProcessArgs, $CompressType
        $ParcompProcessArgs = "{0} -CompressProvider {1}" -f $ParcompProcessArgs, $CompressProvider
        $ParcompProcessArgs = "{0} -deCompressProvider {1}" -f $ParcompProcessArgs, $deCompressProvider
        $ParcompProcessArgs = "{0} -QatCompressionType {1}" -f $ParcompProcessArgs, $QatCompressionType
        $ParcompProcessArgs = "{0} -Level {1}" -f $ParcompProcessArgs, $Level
        $ParcompProcessArgs = "{0} -Chunk {1}" -f $ParcompProcessArgs, $Chunk
        $ParcompProcessArgs = "{0} -blockSize {1}" -f $ParcompProcessArgs, $blockSize
        $ParcompProcessArgs = "{0} -numThreads {1}" -f $ParcompProcessArgs, $numThreads
        $ParcompProcessArgs = "{0} -numIterations {1}" -f $ParcompProcessArgs, $numIterations
        $ParcompProcessArgs = "{0} -TestFileType {1}" -f $ParcompProcessArgs, $TestFileType
        $ParcompProcessArgs = "{0} -TestFileSize {1}" -f $ParcompProcessArgs, $TestFileSize
        $ParcompkeyWords = "{0}_{1}" -f $CompressType, $_
        $ParcompProcessArgs = "{0} -keyWords {1}" -f $ParcompProcessArgs, $ParcompkeyWords
        # $ParcompProcessArgs = "{0} -isDomain {1}" -f $ParcompProcessArgs, $isDomain

        # Delete Start Operation Flag file
        $StartOperationFlagName = "{0}_{1}" -f $StartOperationFlag, $ParcompkeyWords
        $StartOperationFlagPath = "{0}\\{1}" -f $LocalProcessPath, $StartOperationFlagName
        if (Test-Path -Path $StartOperationFlagPath) {
            Get-Item -Path $StartOperationFlagPath | Remove-Item -Recurse -Force | out-null
        }
        $StartOperationFlagArray += $StartOperationFlagName

        $ParcompProcess = WBase-StartProcess `
            -ProcessFilePath "pwsh" `
            -ProcessArgs $ParcompProcessArgs `
            -keyWords $ParcompkeyWords

        $ParcompProcessList[$_] = [hashtable] @{
            Output = $ParcompProcess.Output
            Error = $ParcompProcess.Error
            Result = $ParcompProcess.Result
        }

        $ProcessIDArray += $ParcompProcess.ID
    }

    # Move all VMs
    if ($ReturnValue.result) {
        WTW-ChechFlagFile -FlagFileNameArray $StartOperationFlagArray | out-null

        $MoveVMStatus = Domain-MoveVM `
            -VMNameList $VMNameList `
            -isDomain $isDomain `
            -UseS2D $UseS2D

        if (-not $MoveVMStatus.result) {
            $ReturnValue.result = $MoveVMStatus.result
            $ReturnValue.error = $MoveVMStatus.error
        }

        if (-not (Test-Path -Path $OperationCompletedFlagPath)) {
            New-Item -Path $LocalProcessPath -Name $OperationCompletedFlag -ItemType "file" | out-null
        }
    }

    # Wait for parcomp process
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null

    # Check output and error log for parcomp process
    $VMNameList | ForEach-Object {
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
        Win-DebugTimestamp -output (
            "{0}: The LiveMigration parcomp process ----------------" -f $vmName
        )

        $ParcompProcessResult = WBase-CheckProcessOutput `
            -ProcessOutputLog $ParcompProcessList[$_].Output `
            -ProcessErrorLog $ParcompProcessList[$_].Error `
            -ProcessResult $ParcompProcessList[$_].Result `
            -Remote $false

        if ($ReturnValue.result) {
            $ReturnValue.result = $ParcompProcessResult.result
            $ReturnValue.error = $ParcompProcessResult.error
        }

        if ($ParcompProcessResult.result) {
            Win-DebugTimestamp -output (
                "{0}: The LiveMigration parcomp process ---------------- true" -f $vmName
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: The LiveMigration parcomp process ---------------- false" -f $vmName
            )
        }
    }

    return $ReturnValue
}


Export-ModuleMember -Function *-*
