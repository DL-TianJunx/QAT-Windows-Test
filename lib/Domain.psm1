if (!$QATTESTPATH) {
    $TestSuitePath = Split-Path -Parent (Split-Path -Path $PSCommandPath)
    Set-Variable -Name "QATTESTPATH" -Value $TestSuitePath -Scope global
}

Import-Module "$QATTESTPATH\\lib\\WinBase.psm1" -Force -DisableNameChecking

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
        Param($DomainDriverPath, $DomainResultPath, $BertaConfig)
        $LocationInfo.HVMode = $true
        $LocationInfo.IsWin = $true
        $LocationInfo.VM.IsWin = $true
        $LocationInfo.WriteLogToConsole = $false

        WBase-ReturnFilesInit `
            -BertaResultPath $DomainResultPath `
            -ResultFile "result.log" | out-null
        $PFVFDriverPath = WBase-GetDriverPath -BuildPath $DomainDriverPath

        WBase-LocationInfoInit -BertaResultPath $DomainResultPath `
                               -QatDriverFullPath $PFVFDriverPath `
                               -BertaConfig $BertaConfig | out-null

        return $LocationInfo
    } -ArgumentList $DomainDriverPath, $DomainResultPath, $BertaConfig

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

        [int]$numThreads = 6,

        [int]$numIterations = 200,

        [int]$blockSize = 4096,

        [int]$Chunk = 64,

        [string]$TestFilefullPath = $null,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200,

        [string]$QatDriverZipPath = $null,

        [string]$BertaResultPath = "C:\\temp"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $LiveMTestResultsList = @{
    #     vm = $null
    #     result = $true
    #     error = "no_error"
    # }
    $LiveMTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $LiveMTestResultsList += @{
            vm = $vmName
            result = $true
            error = "no_error"
        }
    }

    $ParcompType = "Fallback"
    $runParcompType = "Process"
    $CompressTestPath = $ParcompOpts.CompressPathName
    $deCompressTestPath = $ParcompOpts.deCompressPathName

    $vmNameBase = $env:COMPUTERNAME
    $RMName = "{0}.QATWSTV_Domain.cc" -f $LocationInfo.Domain.TargetServer
    $DomainPSSession = Domain-PSSessionCreate `
        -RMName $LocationInfo.Domain.TargetServer `
        -PSName $LocationInfo.Domain.PSSession.Name

    # Run tracelog and parcomp exe
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        # Run tracelog
        UT-TraceLogStart -Remote $true -Session $Session | out-null

        Win-DebugTimestamp -output ("{0}: Start to Fallback test ({1}) with {2} provider!" -f $PSSessionName,
                                                                                              $CompressType,
                                                                                              $deCompressProvider)

        $ProcessCount = 0
        if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
            $ProcessCount += 1
            $deCompressTestResult = WBase-Parcomp -Side "remote" `
                                                  -VMNameSuffix $_ `
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
                                                  -TestPathName $deCompressTestPath `
                                                  -TestFilefullPath $TestFilefullPath `
                                                  -TestFileType $TestFileType `
                                                  -TestFileSize $TestFileSize
        }

        if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
            $ProcessCount += 1
            $CompressTestResult = WBase-Parcomp -Side "remote" `
                                                -VMNameSuffix $_ `
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
                                                -TestPathName $CompressTestPath `
                                                -TestFilefullPath $TestFilefullPath `
                                                -TestFileType $TestFileType `
                                                -TestFileSize $TestFileSize
        }

        Start-Sleep -Seconds 10

        # Check parcomp test process number
        $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "parcomp" `
                                                           -ProcessNumber $ProcessCount `
                                                           -Session $Session

        $LiveMTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.result = $CheckProcessNumberFlag.result
                $_.error = $CheckProcessNumberFlag.error
            }
        }
    }

    # Operation: Move vm from the executing machine to the target machine
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)

        # Move all VFs for VM
        HV-AssignableDeviceRemove -VMName $vmName | out-null

        Win-DebugTimestamp -output ("{0}: Start to move vm ...." -f $PSSessionName)
        $DestinationStoragePath = "{0}\\{1}" -f $VHDAndTestFiles.ChildVMPath, $vmName
        Move-VM -Name $vmName `
                -DestinationHost $RMName `
                -IncludeStorage `
                -DestinationStoragePath $DestinationStoragePath | out-null

        $GetVMError = $null
        $VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue -ErrorVariable GetVMError
        if ([String]::IsNullOrEmpty($GetVMError)) {
            Win-DebugTimestamp -output ("{0}: Move vm is unsuccessful" -f $PSSessionName)
            $LiveMTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    $_.result = $false
                    $_.error = "Move_VM_fail"
                }
            }
        } else {
            Win-DebugTimestamp -output ("{0}: Move vm is successful" -f $PSSessionName)
        }
    }

    # reAdd VFs for VMs on the target machine
    if ($ReturnValue.result) {
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSession.Name

        $VMNameList | ForEach-Object {
            Invoke-Command -Session $DomainPSSession -ScriptBlock {
                Param($vmNameBase, $_)
                $vmName = "{0}_{1}" -f $vmNameBase, $_
                $NewvmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
                Rename-VM -Name $vmName -NewName $NewvmName
            } -ArgumentList $vmNameBase, $_ | out-null
        }

        Win-DebugTimestamp -output ("{0}: reAdd VFs on the target machine" -f $DomainPSSession.Name)
        $VMNameList | ForEach-Object {
            $vmName = "{0}_{1}" -f $LocationInfo.Domain.TargetServer, $_
            ForEach ($PFVF in $RemoteInfo.VF.PFVFList[$_]) {
                ForEach ($PFInstance in $RemoteInfo.PF.PCI) {
                    if ([int]($PFVF.PF) -eq [int]($PFInstance.Id)) {
                        Win-DebugTimestamp -output (
                            "{0}: Adding QAT VF to {1} with InstancePath {2} and VF# {3}" -f
                                $DomainPSSession.Name,
                                $vmName,
                                $PFInstance.Instance,
                                $PFVF.VF
                        )

                        Invoke-Command -Session $DomainPSSession -ScriptBlock {
                            Param($vmName, $PFInstance, $PFVF)
                            Add-VMAssignableDevice `
                                -VMName $vmName `
                                -LocationPath $PFInstance.Instance `
                                -VirtualFunction $PFVF.VF | out-null
                        } -ArgumentList $vmName, $PFInstance, $PFVF
                    }
                }
            }
        }

        Win-DebugTimestamp -output ("{0}: Check VFs on the target machine" -f $DomainPSSession.Name)
        $VMNameList | ForEach-Object {
            $vmName = "{0}_{1}" -f $LocationInfo.Domain.TargetServer, $_
            $ReAddDeviceStatus = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                Param($vmName, $PFVFList)
                $ReturnValue = $true

                $CheckStatus = HV-AssignableDeviceCheck `
                    -VMName $vmName `
                    -PFVFArray $PFVFList
                if (-not $CheckStatus) {
                    if ($ReturnValue) {
                        $ReturnValue = $false
                    }
                }

                return $ReturnValue
            } -ArgumentList $vmName, $RemoteInfo.VF.PFVFList[$_]

            if ($ReAddDeviceStatus) {
                Win-DebugTimestamp -output ("{0}: reAdd all VFs on {1} are passed" -f $DomainPSSession.Name, $vmName)
            } else {
                Win-DebugTimestamp -output ("{0}: reAdd all VFs on {1} are failed" -f $DomainPSSession.Name, $vmName)
                if ($ReturnValue.result) {
                    $ReturnValue.result = $ReAddDeviceStatus
                    $ReturnValue.error = "reAdd_device_fail"
                }
            }
        }
    }

    # Wait the parcomp to complete and get test result
    if ($ReturnValue.result) {
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSession.Name

        $VMNameList | ForEach-Object {
            $PSSessionName = "Session_{0}" -f $_
            $vmName = "{0}_{1}" -f $vmNameBase, $_
            $vmNameSuffix = $_

            $CompressTestOutLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $CompressTestPath, $ParcompOpts.OutputLog
            $CompressTestErrorLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $CompressTestPath, $ParcompOpts.ErrorLog
            $deCompressTestOutLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $deCompressTestPath, $ParcompOpts.OutputLog
            $deCompressTestErrorLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $deCompressTestPath, $ParcompOpts.ErrorLog

            $LiveMTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    Win-DebugTimestamp -output (
                        "{0}: {1}: Wait process to complete" -f
                            $DomainPSSession.Name,
                            $PSSessionName
                    )
                    # Wait parcomp test process to complete
                    $WaitProcessFlag = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                        Param($RemoteInfo, $vmNameSuffix)
                        $LocationInfo = $RemoteInfo
                        $PSSessionName = "Session_{0}" -f $vmNameSuffix
                        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $vmNameSuffix
                        $Session = HV-PSSessionCreate `
                            -VMName $vmName `
                            -PSName $PSSessionName `
                            -IsWin $true

                        $WaitProcessFlag = WBase-WaitProcessToCompleted `
                            -ProcessName "parcomp" `
                            -Session $Session `
                            -Remote $true

                        return $WaitProcessFlag
                    } -ArgumentList $RemoteInfo, $vmNameSuffix

                    if ($WaitProcessFlag.result) {
                        Win-DebugTimestamp -output (
                            "{0}: {1}: The process is completed" -f
                                $DomainPSSession.Name,
                                $PSSessionName
                        )
                    } else {
                        Win-DebugTimestamp -output (
                            "{0}: {1}: The process is failed > {2}" -f
                                $DomainPSSession.Name,
                                $PSSessionName,
                                $WaitProcessFlag.error
                        )
                        if ($_.result) {
                            $_.result = $WaitProcessFlag.result
                            $_.error = $WaitProcessFlag.error
                        }
                    }

                    # Check parcomp test result
                    Win-DebugTimestamp -output (
                        "{0}: {1}: Check test result" -f $DomainPSSession.Name, $PSSessionName
                    )

                    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                        $CheckOutput = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                            Param($RemoteInfo, $vmNameSuffix, $CompressTestOutLogPath, $CompressTestErrorLogPath)
                            $LocationInfo = $RemoteInfo
                            $PSSessionName = "Session_{0}" -f $vmNameSuffix
                            $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $vmNameSuffix
                            $Session = HV-PSSessionCreate `
                                -VMName $vmName `
                                -PSName $PSSessionName `
                                -IsWin $true

                            $CheckOutput = WBase-CheckOutput `
                                -TestOutputLog $CompressTestOutLogPath `
                                -TestErrorLog $CompressTestErrorLogPath `
                                -Session $Session `
                                -Remote $true `
                                -keyWords "Mbps"

                            return $CheckOutput
                        } -ArgumentList $RemoteInfo, $vmNameSuffix, $CompressTestOutLogPath, $CompressTestErrorLogPath

                        if ($CheckOutput.result) {
                            Win-DebugTimestamp -output (
                                "{0}: {1}: The Compress test is passed" -f $DomainPSSession.Name, $PSSessionName
                            )
                        } else {
                            Win-DebugTimestamp -output (
                                "{0}: {1}: The Compress test is failed" -f $DomainPSSession.Name, $PSSessionName
                            )
                            if ($_.result) {
                                $_.result = $CheckOutput.result
                                $_.error = $CheckOutput.error
                            }
                        }
                    }

                    if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
                        $CheckOutput = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                            Param($RemoteInfo, $vmNameSuffix, $deCompressTestOutLogPath, $deCompressTestErrorLogPath)
                            $LocationInfo = $RemoteInfo
                            $PSSessionName = "Session_{0}" -f $vmNameSuffix
                            $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $vmNameSuffix
                            $Session = HV-PSSessionCreate `
                                -VMName $vmName `
                                -PSName $PSSessionName `
                                -IsWin $true

                            $CheckOutput = WBase-CheckOutput `
                                -TestOutputLog $deCompressTestOutLogPath `
                                -TestErrorLog $deCompressTestErrorLogPath `
                                -Session $Session `
                                -Remote $true `
                                -keyWords "Mbps"

                            return $CheckOutput
                        } -ArgumentList $RemoteInfo, $vmNameSuffix, $deCompressTestOutLogPath, $deCompressTestErrorLogPath

                        if ($CheckOutput.result) {
                            Win-DebugTimestamp -output (
                                "{0}: {1}: The deCompress test is passed" -f $DomainPSSession.Name, $PSSessionName
                            )
                        } else {
                            Win-DebugTimestamp -output (
                                "{0}: {1}: The deCompress test is failed" -f $DomainPSSession.Name, $PSSessionName
                            )
                            if ($_.result) {
                                $_.result = $CheckOutput.result
                                $_.error = $CheckOutput.error
                            }
                        }
                    }
                }
            }
        }
    }

    # Double check the output files
    if ($ReturnValue.result) {
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSession.Name

        $VMNameList | ForEach-Object {
            $PSSessionName = "Session_{0}" -f $_
            $vmName = "{0}_{1}" -f $vmNameBase, $_
            $vmNameSuffix = $_

            $LiveMTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    if ($_.result) {
                        if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                            Win-DebugTimestamp -output (
                                "{0}: {1}: Double check the output file of LiveM test (compress)" -f
                                    $DomainPSSession.Name,
                                    $PSSessionName
                            )
                            $MD5MatchFlag = $true
                            $CheckMD5Result = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                                Param(
                                    $RemoteInfo,
                                    $vmNameSuffix,
                                    $CompressProvider,
                                    $deCompressProvider,
                                    $QatCompressionType,
                                    $Level,
                                    $Chunk,
                                    $TestFileType,
                                    $TestFileSize,
                                    $CompressTestPath
                                )
                                Import-Module "$QATTESTPATH\\lib\\Win2Win.psm1" -Force -DisableNameChecking
                                $LocationInfo = $RemoteInfo
                                $PSSessionName = "Session_{0}" -f $vmNameSuffix
                                $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $vmNameSuffix
                                $Session = HV-PSSessionCreate `
                                    -VMName $vmName `
                                    -PSName $PSSessionName `
                                    -IsWin $true

                                $CheckMD5Result = WTW-RemoteCheckMD5 `
                                    -Session $Session `
                                    -deCompressFlag $false `
                                    -CompressProvider $CompressProvider `
                                    -deCompressProvider $deCompressProvider `
                                    -QatCompressionType $QatCompressionType `
                                    -Level $Level `
                                    -Chunk $Chunk `
                                    -TestFileType $TestFileType `
                                    -TestFileSize $TestFileSize `
                                    -TestPathName $CompressTestPath

                                return $CheckMD5Result
                            } -ArgumentList $RemoteInfo,
                                            $vmNameSuffix,
                                            $CompressProvider,
                                            $deCompressProvider,
                                            $QatCompressionType,
                                            $Level,
                                            $Chunk,
                                            $TestFileType,
                                            $TestFileSize,
                                            $CompressTestPath

                            $TestSourceFileMD5 = $CheckMD5Result.SourceFile
                            Win-DebugTimestamp -output (
                                "{0}: {1}: The MD5 value of source file > {2}" -f
                                    $DomainPSSession.Name,
                                    $PSSessionName,
                                    $TestSourceFileMD5
                            )
                            $FileCount = 0
                            ForEach ($TestParcompOutFileMD5 in $CheckMD5Result.OutFile) {
                                Win-DebugTimestamp -output (
                                    "{0}: {1}: The MD5 value of LiveM test (compress) output file {2} > {3}" -f
                                        $DomainPSSession.Name,
                                        $PSSessionName,
                                        $FileCount,
                                        $TestParcompOutFileMD5
                                )
                                $FileCount++
                                if ($TestParcompOutFileMD5 -ne $TestSourceFileMD5) {$MD5MatchFlag = $false}
                            }
                            if ($MD5MatchFlag) {
                                Win-DebugTimestamp -output (
                                    "{0}: {1}: The output file of LiveM test (compress) and the source file are matched!" -f
                                        $DomainPSSession.Name,
                                        $PSSessionName
                                )
                            } else {
                                Win-DebugTimestamp -output (
                                    "{0}: {1}: The output file of LiveM test (compress) and the source file are not matched!" -f
                                        $DomainPSSession.Name,
                                        $PSSessionName
                                )

                                $_.result = $false
                                $_.error = "MD5_no_matched"
                            }
                        }

                        if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
                            Win-DebugTimestamp -output (
                                "{0}: {1}: Double check the output file of LiveM test (decompress)" -f
                                    $DomainPSSession.Name,
                                    $PSSessionName
                            )
                            $MD5MatchFlag = $true
                            $CheckMD5Result = Invoke-Command -Session $DomainPSSession -ScriptBlock {
                                Param(
                                    $RemoteInfo,
                                    $vmNameSuffix,
                                    $CompressProvider,
                                    $deCompressProvider,
                                    $QatCompressionType,
                                    $Level,
                                    $Chunk,
                                    $TestFileType,
                                    $TestFileSize,
                                    $deCompressTestPath
                                )
                                Import-Module "$QATTESTPATH\\lib\\Win2Win.psm1" -Force -DisableNameChecking
                                $LocationInfo = $RemoteInfo
                                $PSSessionName = "Session_{0}" -f $vmNameSuffix
                                $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $vmNameSuffix
                                $Session = HV-PSSessionCreate `
                                    -VMName $vmName `
                                    -PSName $PSSessionName `
                                    -IsWin $true

                                    $CheckMD5Result = WTW-RemoteCheckMD5 `
                                        -Session $Session `
                                        -deCompressFlag $true `
                                        -CompressProvider $CompressProvider `
                                        -deCompressProvider $deCompressProvider `
                                        -QatCompressionType $QatCompressionType `
                                        -Level $Level `
                                        -Chunk $Chunk `
                                        -TestFileType $TestFileType `
                                        -TestFileSize $TestFileSize `
                                        -TestPathName $deCompressTestPath

                                return $CheckMD5Result
                            } -ArgumentList $RemoteInfo,
                                            $vmNameSuffix,
                                            $CompressProvider,
                                            $deCompressProvider,
                                            $QatCompressionType,
                                            $Level,
                                            $Chunk,
                                            $TestFileType,
                                            $TestFileSize,
                                            $deCompressTestPath

                            $TestSourceFileMD5 = $CheckMD5Result.SourceFile
                            Win-DebugTimestamp -output (
                                "{0}: {1}: The MD5 value of source file > {2}" -f
                                    $DomainPSSession.Name,
                                    $PSSessionName,
                                    $TestSourceFileMD5
                            )
                            $FileCount = 0
                            ForEach ($TestParcompOutFileMD5 in $CheckMD5Result.OutFile) {
                                Win-DebugTimestamp -output (
                                    "{0}: {1}: The MD5 value of LiveM test (decompress) output file {2} > {3}" -f
                                        $DomainPSSession.Name,
                                        $PSSessionName,
                                        $FileCount,
                                        $TestParcompOutFileMD5
                                )
                                $FileCount++
                                if ($TestParcompOutFileMD5 -ne $TestSourceFileMD5) {$MD5MatchFlag = $false}
                            }
                            if ($MD5MatchFlag) {
                                Win-DebugTimestamp -output (
                                    "{0}: {1}: The output file of LiveM test (decompress) and the source file are matched!" -f
                                        $DomainPSSession.Name,
                                        $PSSessionName
                                )
                            } else {
                                Win-DebugTimestamp -output (
                                    "{0}: {1}: The output file of LiveM test (decompress) and the source file are not matched!" -f
                                        $DomainPSSession.Name,
                                        $PSSessionName
                                )

                                if ($_.result) {$_.result = $false}
                                if ($_.error -ne "MD5_no_matched") {$_.error = "MD5_no_matched"}
                            }
                        }
                    } else {
                        Win-DebugTimestamp -output (
                            "{0}: {1}: Skip checking the output files of LiveM test, because Error > {2}" -f
                                $DomainPSSession.Name,
                                $PSSessionName,
                                $_.error
                        )
                    }
                }
            }
        }
    }

    # Collate return value for all VMs
    if ($ReturnValue.result) {
        $testError = "|"
        $LiveMTestResultsList | ForEach-Object {
            if (!$_.result) {
                $ReturnValue.result = $_.result
                $testError = "{0}{1}->{2}|" -f $testError, $_.vm, $_.error
            }
        }

        if (!$ReturnValue.result) {
            $ReturnValue.error = $testError
        }
    }

    # Run parcomp test after fallback test
    if ($ReturnValue.result) {
        $DomainPSSession = Domain-PSSessionCreate `
            -RMName $LocationInfo.Domain.TargetServer `
            -PSName $LocationInfo.Domain.PSSession.Name

        Win-DebugTimestamp -output (
            "{0}: Double check > Run parcomp test after LiveM test" -f $DomainPSSession.Name
        )
        $parcompTestResult = Invoke-Command -Session $DomainPSSession -ScriptBlock {
            Param(
                $RemoteInfo,
                $CompressProvider,
                $QatCompressionType
            )
            Import-Module "$QATTESTPATH\\lib\\Win2Win.psm1" -Force -DisableNameChecking
            $LocationInfo = $RemoteInfo

            $parcompTestResult = WTW-ParcompBase `
                -deCompressFlag $false `
                -CompressProvider $CompressProvider `
                -deCompressProvider $CompressProvider `
                -QatCompressionType $QatCompressionType `
                -BertaResultPath $LocationInfo.Domain.ResultPath

            return $parcompTestResult
        } -ArgumentList $RemoteInfo,
                        $CompressProvider,
                        $QatCompressionType

        if ($parcompTestResult.result) {
            Win-DebugTimestamp -output (
                "{0}: Double check > simple parcomp test is passed" -f $DomainPSSession.Name
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: Double check > simple parcomp test is failed" -f $DomainPSSession.Name
            )
            $ReturnValue.result = $parcompTestResult.result
            $ReturnValue.error = $parcompTestResult.error
        }
    }

    return $ReturnValue
}


Export-ModuleMember -Function *-*
