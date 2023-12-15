
function DomainCopyDir
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$Destination,

        [string]$Path = $null
    )

    $DomainPSSession = $LocationInfo.Domain.PSSession.Session
    Invoke-Command -Session $DomainPSSession -ScriptBlock {
        Param($Destination)
        if (Test-Path -Path $Destination) {
            Get-Item -Path $Destination | Remove-Item -Recurse
        }

        New-Item -Path $Destination -ItemType Directory | out-null
    } -ArgumentList $Destination | out-null

    if (-not [String]::IsNullOrEmpty($Path)) {
        $CopyPath = "{0}\\*" -f $Path
        Copy-Item `
            -ToSession $DomainPSSession `
            -Path $CopyPath `
            -Destination $Destination `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }
}

function Domain-PSSessionCreate
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$RMName,

        [Parameter(Mandatory=$True)]
        [string]$PSName,

        [bool]$IsWin = $true
    )

    $RMNameReal = "{0}.QATWSTV_Domain.cc" -f $RMName

    $PSSessionStatus = Domain-PSSessionCheck -RMName $RMName -PSName $PSName
    if (-not $PSSessionStatus.result) {
        if ($PSSessionStatus.exist) {
            Domain-PSSessionRemove -PSName $PSName | out-null
        }

        Win-DebugTimestamp -output ("Create PS session named {0} for remote machine named {1}" -f $PSName, $RMName)

        for ($i = 1; $i -lt 50; $i++) {
            try {
                New-PSSession `
                    -ComputerName $RMNameReal `
                    -Credential $DomainCredentials `
                    -Name $PSName | out-null

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
            Import-Module "C:\\QatTestBerta\\lib\\WinBase.psm1" -Force -DisableNameChecking
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

    $RMNameReal = "{0}.QATWSTV_Domain.cc" -f $RMName

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
        [string]$BuildPath
    )

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSession.Name
    $DomainDriverPath = $LocationInfo.Domain.DriverPath
    $DomainResultPath = $LocationInfo.Domain.ResultPath

    Win-DebugTimestamp -output ("Init test ENV on target server....")
    Invoke-Command -ScriptBlock {
        Enable-VMMigration

        Set-VMHost `
            -UseAnyNetworkForMigration $true `
            -VirtualMachineMigrationAuthenticationType "Kerberos"
    } | out-null

    Invoke-Command -Session $DomainPSSession -ScriptBlock {
        Enable-VMMigration

        Set-VMHost `
            -UseAnyNetworkForMigration $true `
            -VirtualMachineMigrationAuthenticationType "Kerberos"
    } | out-null

    Win-DebugTimestamp -output ("{0}: Init test script ...." -f $LocationInfo.Domain.TargetServer)
    Invoke-Command -Session $DomainPSSession -ScriptBlock {
        Import-Module "C:\\QatTestBerta\\lib\\BertaTools.psm1" -Force -DisableNameChecking

        CD C:\
        Berta-ENVInit | out-null
        Berta-CopyTestDir | out-null
    } | out-null

    DomainCopyDir -Path $BuildPath -Destination $DomainDriverPath | out-null
    DomainCopyDir -Destination $DomainResultPath | out-null

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
        [string]$VMVFOSConfig
    )

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSession.Name

    Domain-RemoteRemoveVMs | out-null

    Win-DebugTimestamp -output ("{0}: Init config info for VMVFOS...." -f $LocationInfo.Domain.TargetServer)
    $ReturnValue = Invoke-Command -Session $DomainPSSession -ScriptBlock {
        Param($RemoteInfo, $VMVFOSConfig)
        $LocationInfo = $RemoteInfo
        HV-VMVFConfigInit -VMVFOSConfig $VMVFOSConfig | out-null
        return $LocationInfo
    } -ArgumentList $RemoteInfo, $VMVFOSConfig

    return $ReturnValue
}

function Domain-RemoteRemoveVMs
{
    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSession.Name

    Invoke-Command -Session $DomainPSSession -ScriptBlock {
        $VMList = Get-VM
        if (-not [String]::IsNullOrEmpty($VMList)) {
            Foreach ($VM in $VMList) {
                HV-RemoveVM -VMName $VM.Name | out-null
            }
        }
    } | out-null
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
    $RemoteInfo.WriteLogToFile = $true

    $ParcompType = "Fallback"
    $runParcompType = "Process"
    $ParcompTestResultName = "ProcessResult_{0}.json" -f $keyWords
    $ParcompTestResultPath = "{0}\\{1}" -f $LocalProcessPath, $ParcompTestResultName

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSession.Name

    $PSSessionName = "Session_{0}" -f $VMNameSuffix
    $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
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
            -Side "remote" `
            -VMNameSuffix $VMNameSuffix `
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

        Start-Sleep -Seconds 5
    }

    if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
        $ProcessCount += 1
        $deCompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.deCompressPathName
        $deCompressTestResult = WBase-Parcomp `
            -Side "remote" `
            -VMNameSuffix $VMNameSuffix `
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

        Start-Sleep -Seconds 5
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
    WTW-WaitOperationCompleted | out-null

    # Rename vm on the target machine
    if ($ReturnValue.result) {
        Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param($VMName, $VMNameSuffix)
            $NewVMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
            Rename-VM -Name $VMName -NewName $NewVMName
        } -ArgumentList $VMName, $VMNameSuffix | out-null
    }

    # reAdd VFs for VMs on the target machine
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output ("{0}: reAdd VFs on the target machine" -f $DomainPSSession.Name)
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSession.Name

        $reAddStatus = Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param($RemoteInfo, $VMNameSuffix)
            $ReturnValue = [hashtable] @{
                result = $true
                error = "no_error"
            }

            $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
            $global:LocationInfo = $RemoteInfo
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
        } -ArgumentList $RemoteInfo, $VMNameSuffix

        if ($reAddStatus.result) {
            Win-DebugTimestamp -output ("{0}: reAdd all VFs is passed" -f $DomainPSSession.Name)
        } else {
            Win-DebugTimestamp -output ("{0}: reAdd all VFs is failed" -f $DomainPSSession.Name)
            $ReturnValue.result = $reAddStatus.result
            $ReturnValue.error = $reAddStatus.error

            WBase-WriteHashtableToJsonFile `
                -Info $ReturnValue `
                -InfoFilePath $ParcompTestResultPath | out-null
        }
    }

    # Double check the output log
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: Double check output log on the target machine" -f $DomainPSSession.Name
        )
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSession.Name

        $CheckOutputLogStatus = Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param($RemoteInfo, $VMNameSuffix, $CompressType)
            $ReturnValue = [hashtable] @{
                result = $true
                error = "no_error"
            }

            $PSSessionName = "Session_{0}" -f $VMNameSuffix
            $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false

            $global:LocationInfo = $RemoteInfo

            $WaitStatus = WBase-WaitProcessToCompletedByName `
                -ProcessID "parcomp" `
                -Remote $true `
                -Session $Session
            if (-not $WaitStatus.result) {
                $ReturnValue.result = $WaitStatus.result
                $ReturnValue.error = $WaitStatus.error
                return $ReturnValue
            }

            Start-Sleep -Seconds 3

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
        } -ArgumentList $RemoteInfo, $VMNameSuffix, $CompressType

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
            -PSName $LocationInfo.Domain.PSSession.Name

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
            Param($RemoteInfo, $VMNameSuffix, $ParcompArgs)
            $ReturnValue = [hashtable] @{
                result = $true
                error = "no_error"
            }

            $PSSessionName = "Session_{0}" -f $VMNameSuffix
            $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false

            $global:LocationInfo = $RemoteInfo

            if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                $CompressTestLogPath = "{0}\\{1}" -f
                    $STVWinPath,
                    $ParcompOpts.CompressPathName
                $CheckMD5Result = WBase-CheckOutputFile `
                    -Remote $true `
                    -Session $Session `
                    -deCompressFlag $ParcompArgs.CompressType `
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

            if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
                $deCompressTestLogPath = "{0}\\{1}" -f
                    $STVWinPath,
                    $ParcompOpts.deCompressPathName
                $CheckMD5Result = WBase-CheckOutputFile `
                    -Remote $true `
                    -Session $Session `
                    -deCompressFlag $ParcompArgs.CompressType `
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
        } -ArgumentList $RemoteInfo, $VMNameSuffix, $ParcompArgs

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
            -PSName $LocationInfo.Domain.PSSession.Name

        $SimpleParcompStatus = Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param($RemoteInfo, $VMNameSuffix)
            $ReturnValue = [hashtable] @{
                result = $true
                error = "no_error"
            }

            $PSSessionName = "Session_{0}" -f $VMNameSuffix
            $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false

            $global:LocationInfo = $RemoteInfo

            $ParcompTestResult = WTW-SimpleParcomp -VMNameSuffix $VMNameSuffix
            if (-not $ParcompTestResult.result) {
                $ReturnValue.result = $ParcompTestResult.result
                $ReturnValue.error = $ParcompTestResult.error
            }

            return $ReturnValue
        } -ArgumentList $RemoteInfo, $VMNameSuffix

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

        [string]$TestPath = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray
    $ParcompProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()
    $RMName = "{0}.QATWSTV_Domain.cc" -f $LocationInfo.Domain.TargetServer

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.PathName
    }

    WBase-GenerateInfoFile | out-null
    WBase-WriteHashtableToJsonFile `
        -Info $RemoteInfo `
        -InfoFilePath $RemoteInfoFilePath | out-null

    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSession.Name

    $OperationCompletedFlagPath = "{0}\\{1}" -f
        $LocalProcessPath,
        $OperationCompletedFlag
    if (Test-Path -Path $OperationCompletedFlagPath) {
        Get-Item -Path $OperationCompletedFlagPath | Remove-Item -Recurse -Force
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
        Start-Sleep -Seconds 5

        $VMNameList | ForEach-Object {
            $PSSessionName = "Session_{0}" -f $_
            $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false

            HV-AssignableDeviceRemove -VMName $vmName | out-null

            Win-DebugTimestamp -output ("{0}: Start to move vm ...." -f $PSSessionName)
            $DestinationStoragePath = "{0}\\{1}_{2}" -f
                $VHDAndTestFiles.ChildVMPath,
                $LocationInfo.Domain.TargetServer,
                $_
            Move-VM `
                -Name $vmName `
                -DestinationHost $RMName `
                -IncludeStorage `
                -DestinationStoragePath $DestinationStoragePath | out-null

            $GetVMError = $null
            $VM = Get-VM `
                -Name $vmName `
                -ErrorAction SilentlyContinue `
                -ErrorVariable GetVMError
            if ([String]::IsNullOrEmpty($GetVMError)) {
                Win-DebugTimestamp -output ("{0}: Move vm is unsuccessful" -f $PSSessionName)
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "Move_VM_fail"
                }
            } else {
                Win-DebugTimestamp -output ("{0}: Move vm is successful" -f $PSSessionName)
            }
        }

        if (-not (Test-Path -Path $OperationCompletedFlagPath)) {
            New-Item -Path $LocalProcessPath -Name $OperationCompletedFlag -ItemType "file" | out-null
        }
    }

    # Wait for parcomp process
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null

    $VMNameList | ForEach-Object {
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
        Win-DebugTimestamp -output (
            "Host: The output log of LiveM process ---------------- {0}" -f $vmName
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
            Win-DebugTimestamp -output ("Host: The LiveM(parcomp) test of {0} is passed" -f $vmName)
        } else {
            Win-DebugTimestamp -output ("Host: The LiveM(parcomp) test of {0} is failed" -f $vmName)
        }
    }

    return $ReturnValue
}


Export-ModuleMember -Function *-*
