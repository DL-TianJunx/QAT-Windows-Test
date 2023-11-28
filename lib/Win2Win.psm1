if (!$QATTESTPATH) {
    $TestSuitePath = Split-Path -Parent (Split-Path -Path $PSCommandPath)
    Set-Variable -Name "QATTESTPATH" -Value $TestSuitePath -Scope global
}

Import-Module "$QATTESTPATH\\lib\\WinBase.psm1" -Force -DisableNameChecking

# About VMs
function WTWRestartVMs
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$VMNameList,

        [bool]$StopFlag = $true,

        [bool]$TurnOff = $true,

        [bool]$StartFlag = $true,

        [bool]$WaitFlag = $true,

        [bool]$SessionFlag = $true,

        [bool]$CheckFlag = $true
    )

    if ($StopFlag) {
        $VMNameList | ForEach-Object {
            $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            HV-RestartVMHard `
                -VMName $VMName `
                -StopFlag $StopFlag `
                -TurnOff $TurnOff `
                -StartFlag $false `
                -WaitFlag $false | out-null
        }
    }

    if ($WaitFlag) {
        Start-Sleep -Seconds 60
    }

    if ($StartFlag) {
        $VMNameList | ForEach-Object {
            $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            HV-RestartVMHard `
                -VMName $VMName `
                -StopFlag $false `
                -TurnOff $false `
                -StartFlag $StartFlag `
                -WaitFlag $false | out-null
        }
    }

    if ($WaitFlag) {
        Start-Sleep -Seconds 100
    }

    if ($SessionFlag) {
        $VMNameList | ForEach-Object {
            $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $PSSessionName = ("Session_{0}" -f $_)
            HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $CheckFlag
        }
    }
}

function WTWCreateVMs
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$VMNameList
    )

    $VMNameList | ForEach-Object {
        HV-CreateVM -VMNameSuffix $_ | out-null
    }
}

function WTWRemoveVMs
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$VMNameList
    )

    $VMNameList | ForEach-Object {
        $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        HV-RemoveVM -VMName $VMName | out-null
    }
}

# About test ENV init
function WTW-ENVInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMVFOSConfig,

        [bool]$InitVM = $true
    )

    HV-VMVFConfigInit -VMVFOSConfig $VMVFOSConfig | out-null

    $VMNameList = $LocationInfo.VM.NameArray

    if ($InitVM) {
        # Remove VMs
        WTWRemoveVMs -VMNameList $VMNameList | out-null

        # Create VMs
        WTWCreateVMs -VMNameList $VMNameList | out-null

        # Start VMs
        WTWRestartVMs `
            -VMNameList $VMNameList `
            -StopFlag $false `
            -TurnOff $false `
            -StartFlag $true `
            -WaitFlag $true `
            -SessionFlag $true `
            -CheckFlag $false | out-null
    }

    # Copy Utils and qat windows driver
    $VMNameList | ForEach-Object {
        $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_)
        $Session = HV-PSSessionCreate `
            -VMName $VMName `
            -PSName $PSSessionName `
            -IsWin $true

        # create test base path on VM
        Invoke-Command -Session $Session -ScriptBlock {
            Param($STVWinPath)
            if (-not (Test-Path -Path $STVWinPath)) {
                New-Item -Path $STVWinPath -ItemType Directory
            }
        } -ArgumentList $STVWinPath | out-null

        # copy and unpack qat driver to VM
        $HostQatDriverFullPath = "{0}\\{1}" -f
            $LocalVFDriverPath,
            $LocationInfo.VF.DriverName
        $RemoteQatDriverFullPath = "{0}\\{1}" -f
            $STVWinPath,
            $LocationInfo.VF.DriverName
        $RemoteQatDriverPath = "{0}\\{1}" -f
            $STVWinPath,
            $VMDriverInstallPath.InstallPath

        Copy-Item `
            -ToSession $Session `
            -Path $HostQatDriverFullPath `
            -Destination $RemoteQatDriverFullPath

        Invoke-Command -Session $Session -ScriptBlock {
            Param($RemoteQatDriverFullPath, $RemoteQatDriverPath)
            if (Test-Path -Path $RemoteQatDriverPath) {
                Get-Item -Path $RemoteQatDriverPath | Remove-Item -Recurse
            }
            New-Item -Path $RemoteQatDriverPath -ItemType Directory
            Expand-Archive `
                -Path $RemoteQatDriverFullPath `
                -DestinationPath $RemoteQatDriverPath `
                -Force `
                -ErrorAction Stop
        } -ArgumentList $RemoteQatDriverFullPath, $RemoteQatDriverPath | out-null

        # Copy cert files
        Invoke-Command -Session $Session -ScriptBlock {
            Param($Certificate)
            if (Test-Path -Path $Certificate.Remote) {
                Get-Item -Path $Certificate.Remote | Remove-Item -Recurse
            }
        } -ArgumentList $Certificate | out-null

        if (Test-Path -Path $Certificate.HostVF) {
            Copy-Item `
                -ToSession $Session `
                -Path $Certificate.HostVF `
                -Destination $Certificate.Remote
        }

        # Copy test files
        Foreach ($Type in $TestFileNameArray.Type) {
            if ($Type -eq "high") {continue}
            Foreach ($Size in $TestFileNameArray.Size) {
                $TestFileFullPath = "{0}\\{1}{2}.txt" -f $STVWinPath, $Type, $Size
                if (-not (Invoke-Command -Session $Session -ScriptBlock {
                        Param($TestFileFullPath)
                        Test-Path -Path $TestFileFullPath
                    } -ArgumentList $TestFileFullPath)) {
                    Copy-Item `
                        -ToSession $Session `
                        -Path $TestFileFullPath `
                        -Destination $TestFileFullPath
                }
            }
        }

        # Copy PDB files
        Invoke-Command -Session $Session -ScriptBlock {
            Param($TraceLogOpts)
            if (Test-Path -Path $TraceLogOpts.TraceLogPath) {
                Remove-Item `
                    -Path $TraceLogOpts.TraceLogPath `
                    -Recurse `
                    -Force `
                    -Exclude "*.etl" `
                    -Confirm:$false `
                    -ErrorAction Stop | out-null
            } else {
                New-Item `
                    -Path $TraceLogOpts.TraceLogPath `
                    -ItemType Directory | out-null
            }

            New-Item `
                -Path $TraceLogOpts.FMTPath `
                -ItemType Directory | out-null

            New-Item `
                -Path $TraceLogOpts.PDBPath `
                -ItemType Directory | out-null
        } -ArgumentList $TraceLogOpts | out-null

        $PDBIncludeFiles = @("*.pdb")
        $PDBCopyPath = "{0}\\*" -f $LocalVFDriverPath
        Copy-Item `
            -ToSession $Session `
            -Path $PDBCopyPath `
            -Destination $TraceLogOpts.PDBPath `
            -Include $PDBIncludeFiles `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    # Check and set Test mode and Debug mode and driver verifier
    $RestartVMFlag = $false
    $VMNameList | ForEach-Object {
        $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_)
        $Session = HV-PSSessionCreate `
            -VMName $VMName `
            -PSName $PSSessionName `
            -IsWin $true

        $TestModeStatus = UT-CheckTestMode `
            -CheckFlag $LocationInfo.TestMode `
            -Session $Session `
            -Remote $true

        if (-not $TestModeStatus) {
            UT-SetTestMode `
                -TestMode $LocationInfo.TestMode `
                -Session $Session `
                -Remote $true | out-null

            $RestartVMFlag = $true
        }

        $DebugModeStatus = UT-CheckDebugMode `
            -CheckFlag $LocationInfo.DebugMode `
            -Session $Session `
            -Remote $true

        if (-not $DebugModeStatus) {
            UT-SetDebugMode `
                -DebugMode $LocationInfo.DebugMode `
                -Session $Session `
                -Remote $true | out-null

            $RestartVMFlag = $true
        }

        $DriverVerifierStatus = UT-CheckDriverVerifier `
            -CheckFlag $LocationInfo.VerifierMode `
            -Session $Session `
            -Remote $true

        if (-not $DriverVerifierStatus) {
            UT-SetDriverVerifier `
                -DriverVerifier $LocationInfo.VerifierMode `
                -Session $Session `
                -Remote $true | out-null

            $RestartVMFlag = $true
        }
    }

    if ($RestartVMFlag) {
        # reStart VMs
        WTWRestartVMs `
            -VMNameList $VMNameList `
            -StopFlag $true `
            -TurnOff $false `
            -StartFlag $true `
            -WaitFlag $true `
            -SessionFlag $true | out-null
    }

    if ($InitVM) {
        # Install qat driver on VMs
        $VMNameList | ForEach-Object {
            $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $PSSessionName = ("Session_{0}" -f $_)
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true

            UT-SetCertificate `
                -CertFile $Certificate.Remote `
                -Session $Session `
                -Remote $true

            Win-DebugTimestamp -output (
                "{0}: Install Qat driver on remote windows VM" -f $PSSessionName
            )

            $VMQatSetupPath = "{0}\\{1}\\{2}" -f
                $STVWinPath,
                $VMDriverInstallPath.InstallPath,
                $VMDriverInstallPath.QatSetupPath

            WBase-InstallAndUninstallQatDriver `
                -Session $Session `
                -SetupExePath $VMQatSetupPath `
                -Operation $true `
                -Remote $true `
                -Wait $false `
                -UQMode $LocationInfo.UQMode
        }

        # Wait qat driver to complete on VMs
        $VMNameList | ForEach-Object {
            $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $PSSessionName = ("Session_{0}" -f $_)
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $true

            WBase-WaitProcessToCompleted `
                -ProcessName "QatSetup" `
                -Session $Session `
                -Remote $true | out-null
        }
    }

    # Double check QAT driver installed
    $VMNameList | ForEach-Object {
        $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_)
        $Session = HV-PSSessionCreate `
            -VMName $VMName `
            -PSName $PSSessionName `
            -IsWin $true

        $CheckDriverResult = WBase-CheckDriverInstalled `
            -Remote $true `
            -Session $Session
        if ($CheckDriverResult) {
            $DoubleCheckDriverResult = WBase-DoubleCheckDriver `
                -Remote $true `
                -Session $Session
            if (-not $DoubleCheckDriverResult) {
                throw ("{0}: Qat driver installed is incorrect" -f $PSSessionName)
            }
        } else {
            throw ("{0}: Qat driver is not installed" -f $PSSessionName)
        }

        if ($InitVM) {
            $CheckFlag = WBase-CheckQatDevice `
                -Remote $true `
                -Session $Session `
                -CheckStatus "OK"
            if ($CheckFlag.result) {
                Win-DebugTimestamp -output (
                    "{0}: The number of qat devices is correct > {1}" -f
                        $PSSessionName,
                        $CheckFlag.number
                )
            } else {
                throw ("{0}: The number of QAT devices is incorrect" -f $PSSessionName)
            }
        }
    }

    # Check and set UQ mode
    $VMNameList | ForEach-Object {
        $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_)
        $Session = HV-PSSessionCreate `
            -VMName $VMName `
            -PSName $PSSessionName `
            -IsWin $true

        $DisableDeviceFlag = $false
        $UQModeStatus = UT-CheckUQMode `
            -CheckFlag $LocationInfo.UQMode `
            -Remote $true `
            -Session $Session
        if (-not $UQModeStatus) {
            $DisableDeviceFlag = $true
            UT-SetUQMode `
                -UQMode $LocationInfo.UQMode `
                -Remote $true `
                -Session $Session | out-null
        }

        UT-WorkAround `
            -Remote $true `
            -Session $Session `
            -DisableFlag $DisableDeviceFlag | out-null
    }

    # Run tracelog
    $VMNameList | ForEach-Object {
        $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_)
        $Session = HV-PSSessionCreate `
            -VMName $VMName `
            -PSName $PSSessionName `
            -IsWin $true

        UT-TraceLogStart -Remote $true -Session $Session | out-null
    }
}

# About base test
function WTW-RemoteCheckMD5
{
    Param(
        [Parameter(Mandatory=$True)]
        [object]$Session,

        [bool]$deCompressFlag = $false,

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$Chunk = 64,

        [string]$TestPathName = $null,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200
    )

    $ReturnValue = [hashtable] @{
        SourceFile = $null
        OutFile = $null
    }

    if ([String]::IsNullOrEmpty($TestPathName)) {
        $TestPathName = $ParcompOpts.PathName
    }

    $TestSourceFile = "{0}\\{1}{2}.txt" -f $STVWinPath, $TestFileType, $TestFileSize
    $TestParcompPath = "{0}\\{1}" -f $STVWinPath, $TestPathName
    $deCompressPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.MD5PathName
    $TestParcompOutFileList = @()
    $deCompressSourceFileList = @()
    $TestParcompOutFileMD5List = @()

    $ReturnLists = Invoke-Command -Session $Session -ScriptBlock {
        Param($TestParcompPath, $ParcompOpts, $deCompressFlag, $deCompressPath)
        $ReturnValue = [hashtable] @{
            TestParcompOutFileList = @()
            deCompressSourceFileList = @()
        }

        if (Test-Path -Path $deCompressPath) {
            Get-Item -Path $deCompressPath | Remove-Item -Recurse
        }
        New-Item -Path $deCompressPath -ItemType Directory

        $TestParcompOutFileArray = Get-ChildItem -Path $TestParcompPath
        $TestParcompOutFileArray | ForEach-Object {
            if (($_.Name -ne $ParcompOpts.OutputLog) -and
                ($_.Name -ne $ParcompOpts.ErrorLog) -and
                ($_.Name -ne $ParcompOpts.InputFileName)) {
                $ReturnValue.TestParcompOutFileList += $_.FullName

                if (!$deCompressFlag) {
                    $deCompressSourceFile = "{0}\\{1}" -f $deCompressPath, $_.Name
                    $ReturnValue.deCompressSourceFileList += $deCompressSourceFile
                    Copy-Item -Path $_.FullName -Destination $deCompressSourceFile
                }
            }
        }

        return $ReturnValue
    } -ArgumentList $TestParcompPath, $ParcompOpts, $deCompressFlag, $deCompressPath

    $ReturnLists.TestParcompOutFileList | ForEach-Object {
        if (-not ([String]::IsNullOrEmpty($_))) {
            $TestParcompOutFileList += $_
        }
    }

    $ReturnLists.deCompressSourceFileList | ForEach-Object {
        if (-not ([String]::IsNullOrEmpty($_))) {
            $deCompressSourceFileList += $_
        }
    }

    $TestSourceFileMD5 = Invoke-Command -Session $Session -ScriptBlock {
        Param($TestSourceFile)
        certutil -hashfile $TestSourceFile MD5
    } -ArgumentList $TestSourceFile
    $TestSourceFileMD5 = $TestSourceFileMD5[1]
    #Win-DebugTimestamp -output ("{0}: {1} > {2}" -f $Session.Name, $TestSourceFile, $TestSourceFileMD5)

    if ($deCompressFlag) {
        ForEach ($TestParcompOutFile in $TestParcompOutFileList) {
            $TestParcompOutFileMD5 = Invoke-Command -Session $Session -ScriptBlock {
                Param($TestParcompOutFile)
                certutil -hashfile $TestParcompOutFile MD5
            } -ArgumentList $TestParcompOutFile
            $TestParcompOutFileMD5 = $TestParcompOutFileMD5[1]
            #Win-DebugTimestamp -output ("{0}: {1} > {2}" -f $Session.Name, $TestParcompOutFile, $TestParcompOutFileMD5)
            $TestParcompOutFileMD5List += $TestParcompOutFileMD5
        }
    } else {
        $TestParcompOutFile = "{0}\\{1}" -f $TestParcompPath, $ParcompOpts.OutputFileName
        ForEach ($deCompressSourceFile in $deCompressSourceFileList) {
            $deCompressOut = WBase-Parcomp -Side "remote" `
                                           -VMNameSuffix $vmName.split("_")[1] `
                                           -deCompressFlag $true `
                                           -CompressProvider $CompressProvider `
                                           -deCompressProvider $deCompressProvider `
                                           -QatCompressionType $QatCompressionType `
                                           -Level $Level `
                                           -Chunk $Chunk `
                                           -TestPathName $TestPathName `
                                           -TestFilelocation "VM" `
                                           -TestFilefullPath $deCompressSourceFile

            $TestParcompOutFileMD5 = Invoke-Command -Session $Session -ScriptBlock {
                Param($TestParcompOutFile)
                certutil -hashfile $TestParcompOutFile MD5
            } -ArgumentList $TestParcompOutFile
            $TestParcompOutFileMD5 = $TestParcompOutFileMD5[1]
            #Win-DebugTimestamp -output ("{0}: {1} > {2}" -f $Session.Name, $TestParcompOutFile, $TestParcompOutFileMD5)
            $TestParcompOutFileMD5List += $TestParcompOutFileMD5
        }
    }

    $ReturnValue.SourceFile = $TestSourceFileMD5
    $ReturnValue.OutFile = $TestParcompOutFileMD5List

    return $ReturnValue
}

function WTWRemoteErrorHandle
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$TestResultsList,

        [Parameter(Mandatory=$True)]
        [string]$BertaResultPath,

        [Parameter(Mandatory=$True)]
        [string]$ParameterFileName,

        [bool]$Transfer = $false
    )

    # Stop trace and transfer tracelog file
    $TestResultsList | ForEach-Object {
        if (!$_.result) {
            $vmName = $_.vm
            $PSSessionName = ("Session_{0}" -f $vmName.split("_")[1])
            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true

            UT-TraceLogStop -Remote $true -Session $Session | out-null
            if ($Transfer) {UT-TraceLogTransfer -Remote $true -Session $Session | out-null}
        }
    }

    # Handle:
    #    -process_timeout
    #    -BSOD_error
    #    -Copy tracelog file to 'BertaResultPath'
    $TestResultsList | ForEach-Object {
        if (!$_.result) {
            $vmName = $_.vm
            $PSSessionName = ("Session_{0}" -f $vmName.split("_")[1])

            if ($_.error -eq "process_timeout") {
                Win-DebugTimestamp -output ("{0}: restart the VM because error > {1}" -f $PSSessionName, $_.error)
                HV-RestartVMHard `
                    -VMName $vmName `
                    -StopFlag $true `
                    -TurnOff $true `
                    -StartFlag $true `
                    -WaitFlag $true | out-null
            }

            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true

            if ($_.error -eq "BSOD_error") {
                if (Invoke-Command -Session $Session -ScriptBlock {
                        Param($SiteKeep)
                        Test-Path -Path $SiteKeep.DumpFile
                    } -ArgumentList $SiteKeep) {
                    $Remote2HostDumpFile = "{0}\\Dump_{1}_{2}.DMP" -f
                        $BertaResultPath,
                        $ParameterFileName,
                        $vmName.split("_")[1]
                    Copy-Item -FromSession $Session `
                              -Path $SiteKeep.DumpFile `
                              -Destination $Remote2HostDumpFile `
                              -Force `
                              -Confirm:$false | out-null
                    Invoke-Command -Session $Session -ScriptBlock {
                        Param($SiteKeep)
                        Get-Item -Path $SiteKeep.DumpFile | Remove-Item -Recurse
                    } -ArgumentList $SiteKeep | out-null
                }
            }

            Win-DebugTimestamp -output ("{0}: Copy tracelog etl files to 'BertaResultPath'" -f $PSSessionName)
            $LocationInfo.PDBNameArray.Remote | ForEach-Object {
                $BertaEtlFile = "{0}\\Tracelog_{1}_{2}_{3}.etl" -f
                    $BertaResultPath,
                    $_,
                    $ParameterFileName,
                    $vmName.split("_")[1]
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
                    } -ArgumentList $RemoteEtlFile | out-null
                }
            }
        }
    }
}

# About SWFallback test
function WTWEnableAndDisableQatDevice
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$VMNameList
    )

    $PNPCheckflag = $true

    # disable qat device on each vm
    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $Disableflag = WBase-EnableAndDisableQatDevice -Remote $true `
                                                       -Session $Session `
                                                       -Disable $true `
                                                       -Enable $false `
                                                       -Wait $false

        if ($PNPCheckflag) {
            $PNPCheckflag = $Disableflag
        }
    }

    Start-Sleep -Seconds 30

    # enable qat device on each vm
    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $Enableflag = WBase-EnableAndDisableQatDevice -Remote $true `
                                                      -Session $Session `
                                                      -Disable $false `
                                                      -Enable $true `
                                                      -Wait $false

        if ($PNPCheckflag) {
            $PNPCheckflag = $Enableflag
        }
    }

    Start-Sleep -Seconds 90
    return $PNPCheckflag
}

# Test: installer check
function WTW-InstallerCheckBase
{
    Param(
        [string]$BertaResultPath,

        [bool]$parcompFlag = $true,

        [bool]$cngtestFlag = $false
    )

    # Base on QAT Windows driver installed
    $ReturnValue = [hashtable] @{
        install = [hashtable] @{
            service = [hashtable] @{
                result = $true
                error = "no_error"
            }
            device = [hashtable] @{
                result = $true
                error = "no_error"
            }
            library = [hashtable] @{
                result = $true
                error = "no_error"
            }
        }
        uninstall = [hashtable] @{
            service = [hashtable] @{
                result = $true
                error = "no_error"
            }
            device = [hashtable] @{
                result = $true
                error = "no_error"
            }
            library = [hashtable] @{
                result = $true
                error = "no_error"
            }
        }
        parcomp = [hashtable] @{
            result = $true
            error = "no_error"
        }
        cngtest = [hashtable] @{
            result = $true
            error = "no_error"
        }
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $InstallTestResultsList = @{
    #     vm = $null
    #     service = $true
    #     device = $true
    #     library = $true
    #     parcomp = $true
    #     cngtest = $true
    # }
    $InstallTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $InstallTestResultsList += @{
            vm = $vmName
            service = $true
            device = $true
            library = $true
        }
    }

    # $UninstallTestResultsList = @{
    #     vm = $null
    #     service = $true
    #     device = $true
    #     library = $true
    # }
    $UninstallTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $UninstallTestResultsList += @{
            vm = $vmName
            service = $true
            device = $true
            library = $true
        }
    }

    $CheckTypes = [System.Array] @("service", "device", "library")
    $QatDriverServices = [System.Array] @()
    if ($parcompFlag) {
        $QatDriverServices += $LocationInfo.IcpQatName
        $QatDriverServices += "cfqat"
    }

    if ($cngtestFlag) {$QatDriverServices += "cpmprovuser"}

    $QatDriverLibs = [System.Array] @(
        "C:\\Program Files\\Intel\Intel(R) QuickAssist Technology\\Compression\\Library\\qatzip.lib",
        "C:\\Program Files\\Intel\Intel(R) QuickAssist Technology\\Compression\\Library\\libqatzip.lib"
    )

    # Run QAT Windows driver check: install
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        Foreach ($CheckType in $CheckTypes) {
            Win-DebugTimestamp -output ("{0}: After QAT driver installed, double check > {1}" -f $PSSessionName, $CheckType)
            $CheckTestResult = WBase-CheckQatDriver -Session $Session `
                                                    -Type $CheckType `
                                                    -Operation $true `
                                                    -QatDriverServices $QatDriverServices `
                                                    -QatDriverLibs $QatDriverLibs `
                                                    -Side "remote"

            if ($CheckType -eq "service") {
                $installCheckService = $CheckTestResult
            } elseif ($CheckType -eq "device") {
                $installCheckDevice = $CheckTestResult
            } elseif ($CheckType -eq "library") {
                $installCheckLibrary = $CheckTestResult
            }
        }

        $InstallTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.service = $installCheckService
                $_.device = $installCheckDevice
                $_.library = $installCheckLibrary
            }
        }
    }

    # Run parcomp test after QAT Windows driver installed
    if ($parcompFlag) {
        Win-DebugTimestamp -output ("After QAT driver installed, double check > run parcomp test")
        $parcompTestResult = WTW-ParcompBase `
            -deCompressFlag $false `
            -CompressProvider "qat" `
            -deCompressProvider "qat" `
            -QatCompressionType "dynamic" `
            -BertaResultPath $BertaResultPath

        Win-DebugTimestamp -output ("Running parcomp test is completed > {0}" -f $parcompTestResult.result)

        $ReturnValue.parcomp.result = $parcompTestResult.result
        $ReturnValue.parcomp.error = $parcompTestResult.error
    }

    # Run CNGTest after QAT Windows driver installed
    if ($cngtestFlag) {
        Win-DebugTimestamp -output ("After QAT driver installed, double check > run cngtest")
        $CNGTestTestResult = WTW-CNGTestBase -algo "rsa" -BertaResultPath $BertaResultPath

        Win-DebugTimestamp -output ("Running cngtest is completed > {0}" -f $CNGTestTestResult.result)

        $ReturnValue.cngtest.result = $CNGTestTestResult.result
        $ReturnValue.cngtest.error = $CNGTestTestResult.error
    }

    # Uninstall QAT Windows driver
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        Win-DebugTimestamp -output ("{0}: uninstall Qat driver" -f $PSSessionName)
        $VMQatSetupPath = "{0}\\{1}\\{2}" -f
            $STVWinPath,
            $VMDriverInstallPath.InstallPath,
            $VMDriverInstallPath.QatSetupPath
        WBase-InstallAndUninstallQatDriver -SetupExePath $VMQatSetupPath `
                                           -Operation $false `
                                           -Remote $true `
                                           -Session $Session `
                                           -Wait $false
    }

    # Wait QAT driver to complete on VMs
    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PSSessionName = ("Session_{0}" -f $_.Name)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        WBase-WaitProcessToCompleted  -ProcessName "QatSetup" -Session $Session -Remote $true | out-null
    }

    # Double check QAT driver is uninstalled
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        WBase-CheckDriverInstalled -Remote $true -Session $Session | out-null
    }

    # Run QAT Windows driver check: uninstall
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        Foreach ($CheckType in $CheckTypes) {
            Win-DebugTimestamp -output ("{0}: After QAT driver uninstalled, double check > {1}" -f $PSSessionName, $CheckType)
            $CheckTestResult = WBase-CheckQatDriver -Session $Session `
                                                    -Type $CheckType `
                                                    -Operation $false `
                                                    -QatDriverServices $QatDriverServices `
                                                    -QatDriverLibs $QatDriverLibs `
                                                    -Side "remote"

            if ($CheckType -eq "service") {
                $uninstallCheckService = $CheckTestResult
            } elseif ($CheckType -eq "device") {
                $uninstallCheckDevice = $CheckTestResult
            } elseif ($CheckType -eq "library") {
                $uninstallCheckLibrary = $CheckTestResult
            }
        }

        $UninstallTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.service = $uninstallCheckService
                $_.device = $uninstallCheckDevice
                $_.library = $uninstallCheckLibrary
            }
        }
    }

    # Collate return value
    $InstallServiceError = "|"
    $InstallDeviceError = "|"
    $InstallLibraryError = "|"
    $InstallTestResultsList | ForEach-Object {
        if (!$_.service) {
            $ReturnValue.install.service.result = $false
            $InstallServiceError = "{0}{1}->install_service_fail|" -f $InstallServiceError, $_.vm
        }

        if (!$_.device) {
            $ReturnValue.install.device.result = $false
            $InstallDeviceError = "{0}{1}->install_device_fail|" -f $InstallDeviceError, $_.vm
        }

        if (!$_.library) {
            $ReturnValue.install.library.result = $false
            $InstallLibraryError = "{0}{1}->install_library_fail|" -f $InstallLibraryError, $_.vm
        }
    }

    $UninstallServiceError = "|"
    $UninstallDeviceError = "|"
    $UninstallLibraryError = "|"
    $UninstallTestResultsList | ForEach-Object {
        if (!$_.service) {
            $ReturnValue.uninstall.service.result = $false
            $UninstallServiceError = "{0}{1}->uninstall_service_fail|" -f $UninstallServiceError, $_.vm
        }

        if (!$_.device) {
            $ReturnValue.uninstall.device.result = $false
            $UninstallDeviceError = "{0}{1}->uninstall_service_fail|" -f $UninstallDeviceError, $_.vm
        }

        if (!$_.library) {
            $ReturnValue.uninstall.library.result = $false
            $UninstallLibraryError = "{0}{1}->uninstall_service_fail|" -f $UninstallLibraryError, $_.vm
        }
    }

    if (!$ReturnValue.install.service.result) {$ReturnValue.install.service.error = $InstallServiceError}
    if (!$ReturnValue.install.device.result) {$ReturnValue.install.device.error = $InstallDeviceError}
    if (!$ReturnValue.install.library.result) {$ReturnValue.install.library.error = $InstallLibraryError}
    if (!$ReturnValue.uninstall.service.result) {$ReturnValue.uninstall.service.error = $UninstallServiceError}
    if (!$ReturnValue.uninstall.device.result) {$ReturnValue.uninstall.device.error = $UninstallDeviceError}
    if (!$ReturnValue.uninstall.library.result) {$ReturnValue.uninstall.library.error = $UninstallLibraryError}

    return $ReturnValue
}

# Test: installer disable and enable
function WTW-InstallerCheckDisable
{
    Param(
        [string]$BertaResultPath,

        [bool]$parcompFlag = $true,

        [bool]$cngtestFlag = $false
    )

    # Base on QAT Windows driver installed
    $ReturnValue = [hashtable] @{
        disable = [hashtable] @{
            result = $true
            error = "no_error"
        }
        parcomp = [hashtable] @{
            result = $true
            error = "no_error"
        }
        cngtest = [hashtable] @{
            result = $true
            error = "no_error"
        }
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # Run simple parcomp test to check qat driver work well
    if ($parcompFlag) {
        Win-DebugTimestamp -output ("After QAT driver installed, double check > run parcomp test")
        $parcompTestResult = WTW-ParcompBase `
            -deCompressFlag $false `
            -CompressProvider "qat" `
            -deCompressProvider "qat" `
            -QatCompressionType "dynamic" `
            -BertaResultPath $BertaResultPath

        Win-DebugTimestamp -output ("Running parcomp test is completed > {0}" -f $parcompTestResult.result)

        $ReturnValue.parcomp.result = $parcompTestResult.result
        $ReturnValue.parcomp.error = $parcompTestResult.error
    }

    # Run simple cngtest to check qat driver work well
    if ($cngtestFlag) {
        Win-DebugTimestamp -output ("After QAT driver installed, double check > run cngtest")
        $CNGTestTestResult = WTW-CNGTestBase -algo "rsa"

        Win-DebugTimestamp -output ("Running cngtest is completed > {0}" -f $CNGTestTestResult.result)

        $ReturnValue.cngtest.result = $CNGTestTestResult.result
        $ReturnValue.cngtest.error = $CNGTestTestResult.error
    }

    # Run disable and enable qat device on VMs
    Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on VMs")
    $disableStatus = WTWEnableAndDisableQatDevice -VMNameList $VMNameList

    Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
    if (!$disableStatus) {
        $ReturnValue.disable.result = $disableStatus
        $ReturnValue.disable.error = "disable_failed"
    }

    # Run simple parcomp test again to check qat driver work well
    if ($parcompFlag) {
        Win-DebugTimestamp -output ("After QAT driver disable and enable, double check > run parcomp test")
        $parcompTestResult = WTW-ParcompBase `
            -deCompressFlag $false `
            -CompressProvider "qat" `
            -deCompressProvider "qat" `
            -QatCompressionType "dynamic" `
            -BertaResultPath $BertaResultPath

        Win-DebugTimestamp -output ("Running parcomp test is completed > {0}" -f $parcompTestResult.result)

        if ($ReturnValue.parcomp.result) {
            $ReturnValue.parcomp.result = $parcompTestResult.result
            $ReturnValue.parcomp.error = $parcompTestResult.error
        }
    }

    # Run simple cngtest again to check qat driver work well
    if ($cngtestFlag) {
        Win-DebugTimestamp -output ("After QAT driver disable and enable, double check > run cngtest")
        $CNGTestTestResult = WTW-CNGTestBase -algo "rsa"

        Win-DebugTimestamp -output ("Running cngtest is completed > {0}" -f $CNGTestTestResult.result)

        if ($ReturnValue.cngtest.result) {
            $ReturnValue.cngtest.result = $CNGTestTestResult.result
            $ReturnValue.cngtest.error = $CNGTestTestResult.error
        }
    }

    # No need collate return value
    return $ReturnValue
}

# Test: base test of parcomp
function WTW-ParcompBase
{
    Param(
        [bool]$deCompressFlag = $false,

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$Chunk = 64,

        [string]$TestFilefullPath = $null,

        [string]$TestPathName = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200,

        [string]$TestType = "Parameter"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $ParameterTestResultsList = @{
    #     vm = $null
    #     result = $true
    #     error = "no_error"
    # }
    $ParameterTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $ParameterTestResultsList += @{
            vm = $vmName
            result = $true
            error = "no_error"
        }
    }

    if ([String]::IsNullOrEmpty($TestPathName)) {
        $TestPathName = $ParcompOpts.PathName
    }

    $TestSourceFile = "{0}\\{1}{2}.txt" -f $STVWinPath, $TestFileType, $TestFileSize

    # Run tracelog and parcomp exe
    # Get parcomp test result
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        # Run tracelog
        UT-TraceLogStart -Remote $true -Session $Session | out-null

        if ($deCompressFlag) {
            Win-DebugTimestamp -output ("{0}: Start to {1} test (decompress) with {2} provider!" -f $PSSessionName,
                                                                                                    $TestType,
                                                                                                    $deCompressProvider)
        } else {
            Win-DebugTimestamp -output ("{0}: Start to {1} test (compress) with {2} provider!" -f $PSSessionName,
                                                                                                  $TestType,
                                                                                                  $CompressProvider)
        }

        $ParcompTestResult = WBase-Parcomp -Side "remote" `
                                           -VMNameSuffix $_ `
                                           -deCompressFlag $deCompressFlag `
                                           -CompressProvider $CompressProvider `
                                           -deCompressProvider $deCompressProvider `
                                           -QatCompressionType $QatCompressionType `
                                           -Level $Level `
                                           -Chunk $Chunk `
                                           -TestPathName $TestPathName `
                                           -TestFilefullPath $TestFilefullPath `
                                           -TestFileType $TestFileType `
                                           -TestFileSize $TestFileSize

        $ParameterTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.result = $ParcompTestResult.result
                $_.error = $ParcompTestResult.error
            }
        }
    }

    # Double check the output file
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $ParameterTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                if ($_.result) {
                    Win-DebugTimestamp -output ("{0}: Double check the output file of {1} test" -f $PSSessionName, $TestType)
                    $TestParcompOutFile = "{0}\\{1}\\{2}" -f
                        $STVWinPath,
                        $TestPathName,
                        $ParcompOpts.OutputFileName

                    # The parcomp operation is Compress, need to deCompress the output file and check the match
                    if ($deCompressProvider -eq "7zip") {
                        $TestdeCompressPath = "{0}\\{1}" -f
                            $STVWinPath,
                            $ParcompOpts.sevenZipPathName
                        if (!(Test-Path -Path $TestdeCompressPath)) {
                            New-Item -Path $TestdeCompressPath -ItemType Directory
                        }
                        Copy-Item -FromSession $Session -Path $TestParcompOutFile -Destination $TestdeCompressPath

                        $TestdeCompressInFile = "{0}\\{1}" -f
                            $TestdeCompressPath,
                            $ParcompOpts.OutputFileName
                        $TestdeCompressOutFile = "{0}\\{1}" -f
                            $TestdeCompressPath,
                            ($ParcompOpts.OutputFileName).split(".")[0]
                        if (Test-Path -Path $TestdeCompressOutFile) {
                            Get-Item -Path $TestdeCompressOutFile | Remove-Item -Recurse
                        }

                        Win-DebugTimestamp -output ("{0}: deCompress the output file of {1} test > {2}" -f $PSSessionName, $TestType, $sevenZipExe)
                        $Use7zflag = UT-Use7z -InFile $TestdeCompressInFile -OutFile $TestdeCompressPath
                        $Use7zflagTmp = $null
                        if (!($Use7zflag.gettype().Name -eq "Boolean")) {
                            Foreach ($Member in $Use7zflag) {
                                if ($Member.gettype().Name -eq "Boolean") {
                                    $Use7zflagTmp = $Member
                                }
                            }

                            $Use7zflag = $Use7zflagTmp
                        }

                        if ($Use7zflag) {
                            Win-DebugTimestamp -output ("{0}: The deCompress test is passed" -f $PSSessionName)
                            $TestParcompOutFileMD5 = certutil -hashfile $TestdeCompressOutFile MD5
                            $TestParcompOutFileMD5 = ($TestParcompOutFileMD5).split("\n")[1]

                            $TestSourceFileMD5 = Invoke-Command -Session $Session -ScriptBlock {
                                                                                                 Param($TestSourceFile)
                                                                                                 certutil -hashfile $TestSourceFile MD5
                                                                                                 } -ArgumentList $TestSourceFile
                            $TestSourceFileMD5 = ($TestSourceFileMD5).split("\n")[1]
                        } else {
                            Win-DebugTimestamp -output ("{0}: The deCompress test is false" -f $PSSessionName)
                            $_.result = $false
                            $_.error = "decompress_7zip_failed"
                            return
                        }
                    } else {
                        $CheckMD5Result = WTW-RemoteCheckMD5 -Session $Session `
                                                            -deCompressFlag $deCompressFlag `
                                                            -CompressProvider $CompressProvider `
                                                            -deCompressProvider $deCompressProvider `
                                                            -QatCompressionType $QatCompressionType `
                                                            -Level $Level `
                                                            -Chunk $Chunk `
                                                            -TestPathName $TestPathName `
                                                            -TestFileType $TestFileType `
                                                            -TestFileSize $TestFileSize

                        $TestParcompOutFileMD5 = $CheckMD5Result.OutFile[0]
                        $TestSourceFileMD5 = $CheckMD5Result.SourceFile
                    }

                    Win-DebugTimestamp -output ("{0}: The MD5 value of source file > {1}" -f $PSSessionName, $TestSourceFileMD5)
                    Win-DebugTimestamp -output ("{0}: The MD5 value of {1} test output file > {2}" -f $PSSessionName, $TestType, $TestParcompOutFileMD5)

                    if ($TestParcompOutFileMD5 -eq $TestSourceFileMD5) {
                        Win-DebugTimestamp -output ("{0}: The output file of {1} test and the source file are matched" -f $PSSessionName, $TestType)
                    } else {
                        Win-DebugTimestamp -output ("{0}: The output file of {1} test and the source file are not matched" -f $PSSessionName, $TestType)

                        $_.result = $false
                        $_.error = "MD5_no_matched"
                        return
                    }
                } else {
                    Win-DebugTimestamp -output ("{0}: Skip checking the output file of {1} test, because Error > {2}" -f $PSSessionName, $TestType, $_.error)
                }
            }
        }
    }

    # Collate return value
    $testError = "|"
    $ParameterTestResultsList | ForEach-Object {
        if (!$_.result) {
            $ReturnValue.result = $_.result
            $testError = "{0}{1}->{2}|" -f $testError, $_.vm, $_.error
        }
    }

    if (!$ReturnValue.result) {
        $ReturnValue.error = $testError
    }

    # Handle all error
    if (!$ReturnValue.result) {
        if ($TestType -eq "Parameter") {
            if ($deCompressFlag) {
                $CompressionType = "deCompress"
                $CompressionProvider = $deCompressProvider
            } else {
                $CompressionType = "Compress"
                $CompressionProvider = $CompressProvider
            }

            $ParameterFileName = "{0}_{1}_chunk{3}" -f
                $CompressionType,
                $CompressionProvider,
                $Chunk

            if (!$deCompressFlag) {
                $ParameterFileName = "{0}_level{1}" -f $ParameterFileName, $Level
            }

            if ($deCompressProvider -eq "qat") {
                $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $QatCompressionType
            }
        } elseif ($TestType -eq "Compat") {
            $ParameterFileName = "Compress_{0}_deCompress_{1}" -f $CompressProvider, $deCompressProvider
        }

        WTWRemoteErrorHandle `
            -TestResultsList $ParameterTestResultsList `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName  | out-null
    }

    return $ReturnValue
}

# Test: performance test of parcomp
function WTW-ParcompPerformance
{
    Param(
        [bool]$deCompressFlag = $false,

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$numThreads = 6,

        [int]$numIterations = 200,

        [int]$blockSize = 4096,

        [int]$Chunk = 64,

        [string]$TestFilefullPath = $null,

        [string]$TestPathName = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200,

        [string]$TestType = "Performance"
    )

    # Test type 'Performance' base on 1vm_3vf(QAT17) and 1vm_16vf(QAT20)
    # But this function always support more vms and vfs
    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = 0
        TestFileType = $null
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $PerformanceTestResultsList = @{
    #     vm = $null
    #     result = $true
    #     error = "no_error"
    #     testOps = 0
    # }
    $PerformanceTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $PerformanceTestResultsList += @{
            vm = $vmName
            result = $true
            error = "no_error"
            testOps = 0
        }
    }

    $ParcompType = "Performance"
    $runParcompType = "Process"

    $TestSourceFile = "{0}\\{1}{2}.txt" -f $STVWinPath, $TestFileType, $TestFileSize
    if ([String]::IsNullOrEmpty($TestPathName)) {
        $TestPathName = $ParcompOpts.PathName
    }
    $TestPath = "{0}\\{1}" -f $STVWinPath, $TestPathName
    $TestParcompInFile = "{0}\\{1}" -f $TestPath, $ParcompOpts.InputFileName
    $TestParcompOutFile = "{0}\\{1}" -f $TestPath, $ParcompOpts.OutputFileName
    $TestParcompOutLog = "{0}\\{1}" -f $TestPath, $ParcompOpts.OutputLog
    $TestParcompErrorLog = "{0}\\{1}" -f $TestPath, $ParcompOpts.ErrorLog

    # Stop trace log tool
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        UT-TraceLogStop -Remote $true -Session $Session | out-null
    }

    # Run parcomp exe
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        if ($deCompressFlag) {
            Win-DebugTimestamp -output ("{0}: Start to {1} test (decompress) with {2} provider!" -f $PSSessionName,
                                                                                                    $TestType,
                                                                                                    $deCompressProvider)
        } else {
            Win-DebugTimestamp -output ("{0}: Start to {1} test (compress) with {2} provider!" -f $PSSessionName,
                                                                                                  $TestType,
                                                                                                  $CompressProvider)
        }

        $ParcompTestResult = WBase-Parcomp -Side "remote" `
                                           -VMNameSuffix $_ `
                                           -deCompressFlag $deCompressFlag `
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
                                           -TestPathName $TestPathName `
                                           -TestFilefullPath $TestFilefullPath `
                                           -TestFileType $TestFileType `
                                           -TestFileSize $TestFileSize

        # Check parcomp test process number
        $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "parcomp" -Session $Session
        $PerformanceTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.result = $CheckProcessNumberFlag.result
                $_.error = $CheckProcessNumberFlag.error
                $_.testOps = 0
            }
        }
    }

    # Get parcomp test result
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $PerformanceTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                # Wait parcomp test process to complete
                $WaitProcessFlag = WBase-WaitProcessToCompleted -ProcessName "parcomp" -Session $Session -Remote $true
                if ($_.result) {
                    $_.result = $WaitProcessFlag.result
                    $_.error = $WaitProcessFlag.error
                }

                $Session = HV-PSSessionCreate `
                    -VMName $vmName `
                    -PSName $PSSessionName `
                    -IsWin $true

                # Check parcomp test result
                $CheckOutput = WBase-CheckOutput -TestOutputLog $TestParcompOutLog `
                                                 -TestErrorLog $TestParcompErrorLog `
                                                 -Session $Session `
                                                 -Remote $true `
                                                 -keyWords "Mbps"

                $_.result = $CheckOutput.result
                $_.error = $CheckOutput.error
                $_.testOps = $CheckOutput.testOps
            }
        }
    }

    if ($TestType -eq "Parameter") {
        # Double check the output files
        $VMNameList | ForEach-Object {
            $PSSessionName = ("Session_{0}" -f $_)
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true

            $PerformanceTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    if ($_.result) {
                        Win-DebugTimestamp -output ("{0}: Double check the output file of performance test ({1})" -f $PSSessionName, $TestType)
                        $MD5MatchFlag = $true

                        # The parcomp operation is Compress, need to deCompress the output file and check the match
                        $CheckMD5Result = WTW-RemoteCheckMD5 -Session $Session `
                                                            -deCompressFlag $deCompressFlag `
                                                            -CompressProvider $CompressProvider `
                                                            -deCompressProvider $deCompressProvider `
                                                            -QatCompressionType $QatCompressionType `
                                                            -Level $Level `
                                                            -Chunk $Chunk `
                                                            -TestFileType $TestFileType `
                                                            -TestFileSize $TestFileSize `
                                                            -TestPathName $TestPathName

                        $TestSourceFileMD5 = $CheckMD5Result.SourceFile
                        Win-DebugTimestamp -output ("{0}: The MD5 value of source file > {1}" -f $PSSessionName, $TestSourceFileMD5)
                        $FileCount = 0
                        ForEach ($TestParcompOutFileMD5 in $CheckMD5Result.OutFile) {
                            Win-DebugTimestamp -output ("{0}: The MD5 value of performance test ({1}) output file {2} > {3}" -f $PSSessionName,
                                                                                                                                $TestType,
                                                                                                                                $FileCount,
                                                                                                                                $TestParcompOutFileMD5)
                            $FileCount++
                            if ($TestParcompOutFileMD5 -ne $TestSourceFileMD5) {$MD5MatchFlag = $false}
                        }
                        if ($MD5MatchFlag) {
                            Win-DebugTimestamp -output ("{0}: The output file of performance test ({1}) and the source file are matched" -f $PSSessionName, $TestType)
                        } else {
                            Win-DebugTimestamp -output ("{0}: The output file of performance test ({1}) and the source file are not matched" -f $PSSessionName, $TestType)

                            $_.result = $false
                            $_.error = "MD5_no_matched"
                            return
                        }
                    } else {
                        Win-DebugTimestamp -output ("{0}: Skip checking the output files of performance test ({1}), because Error > {2}" -f $PSSessionName,
                                                                                                                                            $TestType,
                                                                                                                                            $_.error)
                    }
                }
            }
        }
    }

    # Collate return value
    $testError = "|"
    $testOps = 0
    $PerformanceTestResultsList | ForEach-Object {
        $testOps += $_.testOps
        if (!$_.result) {
            $ReturnValue.result = $_.result
            $testError = "{0}{1}->{2}|" -f $testError, $_.vm, $_.error
        }
    }

    if (!$ReturnValue.result) {
        $ReturnValue.error = $testError
    }

    $ReturnValue.testOps = [int]($testOps / $VMNameList.length)
    $ReturnValue.TestFileType = $TestFileType

    # Handle all errors
    if (!$ReturnValue.result) {
        if ($deCompressFlag) {
            $CompressionType = "deCompress"
            $CompressionProvider = $deCompressProvider
        } else {
            $CompressionType = "Compress"
            $CompressionProvider = $CompressProvider
        }

        if ($TestType -eq "Performance") {
            $ParameterFileName = "{0}_{1}_{2}{3}_chunk{4}_blockSize{5}" -f
                $CompressionType,
                $CompressionProvider,
                $TestFileType,
                $TestFileSize,
                $Chunk,
                $blockSize
        } elseif ($TestType -eq "Parameter") {
            $ParameterFileName = "{0}_{1}_threads{2}_iterations{3}_chunk{4}_blockSize{5}" -f
                $CompressionType,
                $CompressionProvider,
                $numThreads,
                $numIterations,
                $Chunk,
                $blockSize
        }

        if (!$deCompressFlag) {
            $ParameterFileName = "{0}_level{1}" -f $ParameterFileName, $Level
        }

        if ($deCompressProvider -eq "qat") {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $QatCompressionType
        }

        WTWRemoteErrorHandle `
            -TestResultsList $PerformanceTestResultsList `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName  | out-null
    }

    return $ReturnValue
}

# Test: SWFallback test of parcomp
function WTW-ParcompSWfallback
{
    Param(
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

        [string]$TestType = "heartbeat",

        [string]$QatDriverZipPath = $null,

        [string]$BertaResultPath = "C:\\temp"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $FallbackTestResultsList = @{
    #     vm = $null
    #     result = $true
    #     error = "no_error"
    # }
    $FallbackTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $FallbackTestResultsList += @{
            vm = $vmName
            result = $true
            error = "no_error"
        }
    }

    $SWFallbackCheck = [hashtable] @{
        Hardware2Software = "Hardware compression failed, attempting software fallback"
        HandleQATError = "handleQatError() failed"
        HandleSWFallbackError = "handleSWFallback() failed"
    }

    $ParcompType = "Fallback"
    $runParcompType = "Process"
    $CompressTestPath = $ParcompOpts.CompressPathName
    $deCompressTestPath = $ParcompOpts.deCompressPathName

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

        Win-DebugTimestamp -output ("{0}: Start to {1} test ({2}) with {3} provider!" -f $PSSessionName,
                                                                                         $TestType,
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

        $FallbackTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.result = $CheckProcessNumberFlag.result
                $_.error = $CheckProcessNumberFlag.error
            }
        }
    }

    # Operation: heartbeat, disable, upgrade
    if ($TestType -eq "heartbeat") {
        Win-DebugTimestamp -output ("Run 'heartbeat' operation on local host")
        $heartbeatStatus = WBase-HeartbeatQatDevice -LogPath $BertaResultPath

        Win-DebugTimestamp -output ("The heartbeat operation > {0}" -f $heartbeatStatus)
        if (!$heartbeatStatus) {
            $ReturnValue.result = $heartbeatStatus
            $ReturnValue.error = "heartbeat_failed"
        }
    } elseif ($TestType -eq "disable") {
        Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on VMs")
        $disableStatus = WTWEnableAndDisableQatDevice -VMNameList $VMNameList

        Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
        if (!$disableStatus) {
            $ReturnValue.result = $disableStatus
            $ReturnValue.error = "disable_failed"
        }
    } elseif ($TestType -eq "upgrade") {
        Win-DebugTimestamp -output ("Run 'upgrade' operation on local host")
        $upgradeStatus = WBase-UpgradeQatDevice

        Win-DebugTimestamp -output ("The upgrade operation > {0}" -f $upgradeStatus)
        if (!$upgradeStatus) {
            $ReturnValue.result = $upgradeStatus
            $ReturnValue.error = "upgrade_failed"
        }
    } else {
        Win-DebugTimestamp -output ("The fallback test does not support test type > {0}" -f $TestType)
        $ReturnValue.result = $false
        $ReturnValue.error = ("test_type_{0}" -f $TestType)
    }

    # Get parcomp test result
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $CompressTestOutLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $CompressTestPath, $ParcompOpts.OutputLog
        $CompressTestErrorLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $CompressTestPath, $ParcompOpts.ErrorLog
        $deCompressTestOutLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $deCompressTestPath, $ParcompOpts.OutputLog
        $deCompressTestErrorLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $deCompressTestPath, $ParcompOpts.ErrorLog

        $FallbackTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                # Wait parcomp test process to complete
                $WaitProcessFlag = WBase-WaitProcessToCompleted -ProcessName "parcomp" -Session $Session -Remote $true
                if ($_.result) {
                    $_.result = $WaitProcessFlag.result
                    $_.error = $WaitProcessFlag.error
                }

                $Session = HV-PSSessionCreate `
                    -VMName $vmName `
                    -PSName $PSSessionName `
                    -IsWin $true

                # Check parcomp test result
                if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                    $CheckOutput = WBase-CheckOutput -TestOutputLog $CompressTestOutLogPath `
                                                     -TestErrorLog $CompressTestErrorLogPath `
                                                     -Session $Session `
                                                     -Remote $true `
                                                     -keyWords "Mbps"

                    if ($_.result) {
                        $_.result = $CheckOutput.result
                        $_.error = $CheckOutput.error
                    }
                }

                if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
                    $CheckOutput = WBase-CheckOutput -TestOutputLog $deCompressTestOutLogPath `
                                                     -TestErrorLog $deCompressTestErrorLogPath `
                                                     -Session $Session `
                                                     -Remote $true `
                                                     -keyWords "Mbps"

                    if ($_.result) {
                        $_.result = $CheckOutput.result
                        $_.error = $CheckOutput.error
                    }
                }
            }
        }
    }

    # Double check the output files
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $FallbackTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                if ($_.result) {
                    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                        Win-DebugTimestamp -output ("{0}: Double check the output file of fallback test (compress)" -f $PSSessionName)
                        $MD5MatchFlag = $true
                        $CheckMD5Result = WTW-RemoteCheckMD5 -Session $Session `
                                                            -deCompressFlag $false `
                                                            -CompressProvider $CompressProvider `
                                                            -deCompressProvider $deCompressProvider `
                                                            -QatCompressionType $QatCompressionType `
                                                            -Level $Level `
                                                            -Chunk $Chunk `
                                                            -TestFileType $TestFileType `
                                                            -TestFileSize $TestFileSize `
                                                            -TestPathName $CompressTestPath

                        $TestSourceFileMD5 = $CheckMD5Result.SourceFile
                        Win-DebugTimestamp -output ("{0}: The MD5 value of source file > {1}" -f $PSSessionName, $TestSourceFileMD5)
                        $FileCount = 0
                        ForEach ($TestParcompOutFileMD5 in $CheckMD5Result.OutFile) {
                            Win-DebugTimestamp -output ("{0}: The MD5 value of fallback test (compress) output file {1} > {2}" -f $PSSessionName, $FileCount, $TestParcompOutFileMD5)
                            $FileCount++
                            if ($TestParcompOutFileMD5 -ne $TestSourceFileMD5) {$MD5MatchFlag = $false}
                        }
                        if ($MD5MatchFlag) {
                            Win-DebugTimestamp -output ("{0}: The output file of fallback test (compress) and the source file are matched!" -f $PSSessionName)
                        } else {
                            Win-DebugTimestamp -output ("{0}: The output file of fallback test (compress) and the source file are not matched!" -f $PSSessionName)

                            $_.result = $false
                            $_.error = "MD5_no_matched"
                        }
                    }

                    if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
                        Win-DebugTimestamp -output ("{0}: Double check the output file of fallback test (decompress)" -f $PSSessionName)
                        $MD5MatchFlag = $true
                        $CheckMD5Result = WTW-RemoteCheckMD5 -Session $Session `
                                                            -deCompressFlag $true `
                                                            -CompressProvider $CompressProvider `
                                                            -deCompressProvider $deCompressProvider `
                                                            -QatCompressionType $QatCompressionType `
                                                            -Level $Level `
                                                            -Chunk $Chunk `
                                                            -TestFileType $TestFileType `
                                                            -TestFileSize $TestFileSize `
                                                            -TestPathName $deCompressTestPath

                        $TestSourceFileMD5 = $CheckMD5Result.SourceFile
                        Win-DebugTimestamp -output ("{0}: The MD5 value of source file > {1}" -f $PSSessionName, $TestSourceFileMD5)
                        $FileCount = 0
                        ForEach ($TestParcompOutFileMD5 in $CheckMD5Result.OutFile) {
                            Win-DebugTimestamp -output ("{0}: The MD5 value of fallback test (decompress) output file {1} > {2}" -f $PSSessionName, $FileCount, $TestParcompOutFileMD5)
                            $FileCount++
                            if ($TestParcompOutFileMD5 -ne $TestSourceFileMD5) {$MD5MatchFlag = $false}
                        }
                        if ($MD5MatchFlag) {
                            Win-DebugTimestamp -output ("{0}: The output file of fallback test (decompress) and the source file are matched!" -f $PSSessionName)
                        } else {
                            Win-DebugTimestamp -output ("{0}: The output file of fallback test (decompress) and the source file are not matched!" -f $PSSessionName)

                            if ($_.result) {$_.result = $false}
                            if ($_.error -ne "MD5_no_matched") {$_.error = "MD5_no_matched"}
                        }
                    }
                } else {
                    Win-DebugTimestamp -output ("{0}: Skip checking the output files of fallback test, because Error > {1}" -f $PSSessionName, $_.error)
                }
            }
        }
    }

    # Collate return value for all VMs
    if ($ReturnValue.result) {
        $testError = "|"
        $FallbackTestResultsList | ForEach-Object {
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
        Win-DebugTimestamp -output ("Double check: Run parcomp test after fallback test")
        $parcompTestResult = WTW-ParcompBase `
            -deCompressFlag $false `
            -CompressProvider $CompressProvider `
            -deCompressProvider $CompressProvider `
            -QatCompressionType $QatCompressionType `
            -BertaResultPath $BertaResultPath

        if (!$parcompTestResult.result) {
            $ReturnValue.result = $parcompTestResult.result
            $ReturnValue.error = $parcompTestResult.error
        }
    }

    # Handle all errors
    if (!$ReturnValue.result) {
        $ParameterFileName = "{0}_{1}_{2}" -f
            $CompressType,
            $CompressProvider,
            $TestType

        if ($ReturnValue.error -eq "heartbeat_failed") {
            $LocationInfo.PDBNameArray.Host | ForEach-Object {
                $BertaEtlFile = "{0}\\Tracelog_{1}_{2}_host.etl" -f
                    $BertaResultPath,
                    $_,
                    $ParameterFileName
                $LocalEtlFile = $TraceLogOpts.EtlFullPath[$_]
                if (Test-Path -Path $LocalEtlFile) {
                    Copy-Item -Path $LocalEtlFile -Destination $BertaEtlFile -Force -Confirm:$false | out-null
                    Get-Item -Path $LocalEtlFile | Remove-Item -Recurse
                }
            }
        }

        WTWRemoteErrorHandle `
            -TestResultsList $FallbackTestResultsList `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName  | out-null
    }

    return $ReturnValue
}

# Test: base test of CNGTest
function WTW-CNGTestBase
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$algo,

        [string]$operation = "encrypt",

        [string]$provider = "qa",

        [int]$keyLength = 2048,

        [string]$ecccurve = "nistP256",

        [string]$padding = "pkcs1",

        [string]$numThreads = 96,

        [string]$numIter = 10000,

        [string]$TestPathName = $null,

        [string]$BertaResultPath = "C:\\temp"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $CNGTestResultsList = @{
    #     vm = $null
    #     result = $true
    #     error = "no_error"
    # }
    $CNGTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $CNGTestResultsList += @{
            vm = $vmName
            result = $true
            error = "no_error"
        }
    }

    if ([String]::IsNullOrEmpty($TestPathName)) {
        $TestPathName = $CNGTestOpts.PathName
    }

    $TestPath = "{0}\\{1}" -f $STVWinPath, $TestPathName
    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog

    # Run tracelog and CNGTest exe
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        # Run tracelog
        UT-TraceLogStart -Remote $true -Session $Session | out-null

        Win-DebugTimestamp -output ("{0}: Start to {1} test ({2}) with {3} provider!" -f $PSSessionName,
                                                                                         $algo,
                                                                                         $operation,
                                                                                         $provider)

        $CNGTestResult = WBase-CNGTest -Side "remote" `
                                       -VMNameSuffix $_ `
                                       -algo $algo `
                                       -operation $operation `
                                       -provider $provider `
                                       -keyLength $keyLength `
                                       -ecccurve $ecccurve `
                                       -padding $padding `
                                       -numThreads $numThreads `
                                       -numIter $numIter `
                                       -TestPathName $TestPathName

        # Check cngtest test process number
        $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "cngtest" -Session $Session
        $CNGTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.result = $CheckProcessNumberFlag.result
                $_.error = $CheckProcessNumberFlag.error
            }
        }
    }

    # Get CNGTest test result
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $CNGTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                # Wait cngtest test process to complete
                $WaitProcessFlag = WBase-WaitProcessToCompleted -ProcessName "cngtest" -Session $Session -Remote $true
                if ($_.result) {
                    $_.result = $WaitProcessFlag.result
                    $_.error = $WaitProcessFlag.error
                }

                $Session = HV-PSSessionCreate `
                    -VMName $vmName `
                    -PSName $PSSessionName `
                    -IsWin $true

                # Check cngtest test output log
                $CheckOutput = WBase-CheckOutput -TestOutputLog $CNGTestOutLog `
                                                 -TestErrorLog $CNGTestErrorLog `
                                                 -Session $Session `
                                                 -Remote $true `
                                                 -keyWords "Ops/s"

                if ($_.result) {
                    $_.result = $CheckOutput.result
                    $_.error = $CheckOutput.error
                }
            }
        }
    }

    # Collate return value
    $testError = "|"
    $CNGTestResultsList | ForEach-Object {
        if (!$_.result) {
            $ReturnValue.result = $_.result
            $testError = "{0}{1}->{2}|" -f $testError, $_.vm, $_.error
        }
    }

    if (!$ReturnValue.result) {
        $ReturnValue.error = $testError
    }

    # Handle all errors
    if (!$ReturnValue.result) {
        $ParameterFileName = "{0}_{1}_{2}" -f
            $provider,
            $algo,
            $operation

        if (($algo -eq "ecdsa") -and ($algo -eq "ecdh")) {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $ecccurve
        } else {
            $ParameterFileName = "{0}_keyLength{1}" -f $ParameterFileName, $keyLength
        }

        if ($algo -eq "rsa") {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $padding
        }

        WTWRemoteErrorHandle `
            -TestResultsList $CNGTestResultsList `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName  | out-null
    }

    return $ReturnValue
}

# Test: performance test of CNGTest
function WTW-CNGTestPerformance
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$algo,

        [string]$operation = "encrypt",

        [string]$provider = "qa",

        [int]$keyLength = 2048,

        [string]$ecccurve = "nistP256",

        [string]$padding = "pkcs1",

        [string]$numThreads = 96,

        [string]$numIter = 10000,

        [string]$TestPathName = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestType = "Performance"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        testOps = 0
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $CNGTestResultsList = @{
    #     vm = $null
    #     result = $true
    #     error = "no_error"
    #     testOps = 0
    # }
    $CNGTestResultsList = @()
    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $CNGTestResultsList += @{
            vm = $vmName
            result = $true
            error = "no_error"
        }
    }

    if ([String]::IsNullOrEmpty($TestPathName)) {
        $TestPathName = $CNGTestOpts.PathName
    }

    $TestPath = "{0}\\{1}" -f $STVWinPath, $TestPathName
    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog

    # Stop trace log tool
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        UT-TraceLogStop -Remote $true -Session $Session | out-null
    }

    # Run CNGTest exe
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        Win-DebugTimestamp -output ("{0}: Start to {1} test ({2}) with {3} provider!" -f $PSSessionName,
                                                                                         $algo,
                                                                                         $operation,
                                                                                         $provider)

        $CNGTestResult = WBase-CNGTest -Side "remote" `
                                       -VMNameSuffix $_ `
                                       -algo $algo `
                                       -operation $operation `
                                       -provider $provider `
                                       -keyLength $keyLength `
                                       -ecccurve $ecccurve `
                                       -padding $padding `
                                       -numThreads $numThreads `
                                       -numIter $numIter `
                                       -TestPathName $TestPathName

        # Check cngtest test process number
        $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "cngtest" -Session $Session
        $CNGTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.result = $CheckProcessNumberFlag.result
                $_.error = $CheckProcessNumberFlag.error
            }
        }
    }

    # Get CNGTest test result
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $CNGTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                # Wait cngtest test process to complete
                $WaitProcessFlag = WBase-WaitProcessToCompleted -ProcessName "cngtest" -Session $Session -Remote $true
                if ($_.result) {
                    $_.result = $WaitProcessFlag.result
                    $_.error = $WaitProcessFlag.error
                }

                $Session = HV-PSSessionCreate `
                    -VMName $vmName `
                    -PSName $PSSessionName `
                    -IsWin $true

                # Check cngtest test output log
                $CheckOutput = WBase-CheckOutput -TestOutputLog $CNGTestOutLog `
                                                 -TestErrorLog $CNGTestErrorLog `
                                                 -Session $Session `
                                                 -Remote $true `
                                                 -keyWords "Ops/s"

                $_.result = $CheckOutput.result
                $_.error = $CheckOutput.error
                $_.testOps = $CheckOutput.testOps
            }
        }
    }

    # Collate return value
    $testError = "|"
    $testOps = 0
    $CNGTestResultsList | ForEach-Object {
        $testOps += $_.testOps
        if (!$_.result) {
            $ReturnValue.result = $_.result
            $testError = "{0}{1}->{2}|" -f $testError, $_.vm, $_.error
        }
    }

    if (!$ReturnValue.result) {
        $ReturnValue.error = $testError
    }

    $ReturnValue.testOps = [int]($testOps / $VMNameList.length)

    # Handle all errors
    if (!$ReturnValue.result) {
        $ParameterFileName = "{0}_{1}_{2}" -f
            $provider,
            $algo,
            $operation

        if (($algo -eq "ecdsa") -and ($algo -eq "ecdh")) {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $ecccurve
        } else {
            $ParameterFileName = "{0}_keyLength{1}" -f $ParameterFileName, $keyLength
        }

        if ($algo -eq "rsa") {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $padding
        }

        WTWRemoteErrorHandle `
            -TestResultsList $CNGTestResultsList `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName  | out-null
    }

    return $ReturnValue
}

# Test: SWFallback test of CNGTest
function WTW-CNGTestSWfallback
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$algo,

        [string]$operation = "encrypt",

        [string]$provider = "qa",

        [int]$keyLength = 2048,

        [string]$ecccurve = "nistP256",

        [string]$padding = "pkcs1",

        [string]$numThreads = 96,

        [string]$numIter = 10000,

        [string]$TestPathName = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestType = "heartbeat"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $CNGTestResultsList = @{
    #     vm = $null
    #     result = $true
    #     error = "no_error"
    # }
    $CNGTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $CNGTestResultsList += @{
            vm = $vmName
            result = $true
            error = "no_error"
        }
    }

    if ([String]::IsNullOrEmpty($TestPathName)) {
        $TestPathName = $CNGTestOpts.PathName
    }

    $TestPath = "{0}\\{1}" -f $STVWinPath, $TestPathName
    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog

    # Run tracelog and CNGTest exe
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        # Run tracelog
        UT-TraceLogStart -Remote $true -Session $Session | out-null

        Win-DebugTimestamp -output ("{0}: Start to {1} test ({2}) with {3} operation!" -f $PSSessionName,
                                                                                         $TestType,
                                                                                         $algo,
                                                                                         $operation)

        $CNGTestResult = WBase-CNGTest -Side "remote" `
                                       -VMNameSuffix $_ `
                                       -algo $algo `
                                       -operation $operation `
                                       -provider $provider `
                                       -keyLength $keyLength `
                                       -ecccurve $ecccurve `
                                       -padding $padding `
                                       -numThreads $numThreads `
                                       -numIter $numIter `
                                       -TestPathName $TestPathName

        Start-Sleep -Seconds 10

        # Check cngtest test process number
        $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "cngtest" -Session $Session
        $CNGTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                $_.result = $CheckProcessNumberFlag.result
                $_.error = $CheckProcessNumberFlag.error
            }
        }
    }

    # Operation: heartbeat, disable, upgrade
    if ($TestType -eq "heartbeat") {
        Win-DebugTimestamp -output ("Run 'heartbeat' operation on local host")
        $heartbeatStatus = WBase-HeartbeatQatDevice -LogPath $BertaResultPath

        Win-DebugTimestamp -output ("The heartbeat operation > {0}" -f $heartbeatStatus)
        if (!$heartbeatStatus) {
            $ReturnValue.result = $heartbeatStatus
            $ReturnValue.error = "heartbeat_failed"
        }
    } elseif ($TestType -eq "disable") {
        Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on VMs")
        $disableStatus = WTWEnableAndDisableQatDevice -VMNameList $VMNameList

        Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
        if (!$disableStatus) {
            $ReturnValue.result = $disableStatus
            $ReturnValue.error = "disable_failed"
        }
    } elseif ($TestType -eq "upgrade") {
        Win-DebugTimestamp -output ("Run 'upgrade' operation on local host")
        $upgradeStatus = WBase-UpgradeQatDevice

        Win-DebugTimestamp -output ("The upgrade operation > {0}" -f $upgradeStatus)
        if (!$upgradeStatus) {
            $ReturnValue.result = $upgradeStatus
            $ReturnValue.error = "upgrade_failed"
        }
    } else {
        Win-DebugTimestamp -output ("The fallback test does not support test type > {0}" -f $TestType)
        $ReturnValue.result = $false
        $ReturnValue.error = ("test_type_{0}" -f $TestType)
    }

    # Get CNGTest test result
    $VMNameList | ForEach-Object {
        $PSSessionName = ("Session_{0}" -f $_)
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true

        $CNGTestResultsList | ForEach-Object {
            if ($_.vm -eq $vmName) {
                # Wait cngtest test process to complete
                $WaitProcessFlag = WBase-WaitProcessToCompleted -ProcessName "cngtest" -Session $Session -Remote $true
                if ($_.result) {
                    $_.result = $WaitProcessFlag.result
                    $_.error = $WaitProcessFlag.error
                }

                $Session = HV-PSSessionCreate `
                    -VMName $vmName `
                    -PSName $PSSessionName `
                    -IsWin $true

                # Check cngtest test output log
                $CheckOutput = WBase-CheckOutput -TestOutputLog $CNGTestOutLog `
                                                 -TestErrorLog $CNGTestErrorLog `
                                                 -Session $Session `
                                                 -Remote $true `
                                                 -keyWords "Ops/s"

                if ($_.result) {
                    $_.result = $CheckOutput.result
                    $_.error = $CheckOutput.error
                }
            }
        }
    }

    # Collate return value for all VMs
    if ($ReturnValue.result) {
        $testError = "|"
        $CNGTestResultsList | ForEach-Object {
            if (!$_.result) {
                $ReturnValue.result = $_.result
                $testError = "{0}{1}->{2}|" -f $testError, $_.vm, $_.error
            }
        }

        if (!$ReturnValue.result) {
            $ReturnValue.error = $testError
        }
    }

    # Run CNGTest after fallback test
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output ("Double check: Run CNGTest after fallback test")

        $CNGTestTestResult = WTW-CNGTestBase -algo $algo

        Win-DebugTimestamp -output ("Running cngtest is completed > {0}" -f $CNGTestTestResult.result)

        $ReturnValue.result = $CNGTestTestResult.result
        $ReturnValue.error = $CNGTestTestResult.error
    }

    # Handle all errors
    if (!$ReturnValue.result) {
        $ParameterFileName = "{0}_{1}_{2}" -f
            $provider,
            $algo,
            $operation

        if (($algo -eq "ecdsa") -and ($algo -eq "ecdh")) {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $ecccurve
        } else {
            $ParameterFileName = "{0}_keyLength{1}" -f $ParameterFileName, $keyLength
        }

        if ($algo -eq "rsa") {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $padding
        }

        $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $TestType

        if ($ReturnValue.error -eq "heartbeat_failed") {
            $LocationInfo.PDBNameArray.Host | ForEach-Object {
                $BertaEtlFile = "{0}\\Tracelog_{1}_{2}_host.etl" -f
                    $BertaResultPath,
                    $_,
                    $ParameterFileName
                $LocalEtlFile = $TraceLogOpts.EtlFullPath[$_]
                if (Test-Path -Path $LocalEtlFile) {
                    Copy-Item -Path $LocalEtlFile -Destination $BertaEtlFile -Force -Confirm:$false | out-null
                    Get-Item -Path $LocalEtlFile | Remove-Item -Recurse
                }
            }
        }

        WTWRemoteErrorHandle `
            -TestResultsList $CNGTestResultsList `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName | out-null
    }

    return $ReturnValue
}

# Test: stress test of parcomp and CNGTest
function WTW-Stress
{
    Param(
        [bool]$RunParcomp = $true,

        [bool]$RunCNGtest = $true,

        [string]$BertaResultPath = "C:\\temp"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $VMNameList = $LocationInfo.VM.NameArray

    # $StressTestResultsList = @{
    #     vm = $null
    #     parcomp = $true
    #     cng = $true
    #     cngerror = "no_error"
    #     parcomperror = "no_error"
    # }
    $StressTestResultsList = @()

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        $StressTestResultsList += @{
            vm = $vmName
            parcomp = $true
            cng = $true
            parcomperror = "no_error"
            cngerror = "no_error"
        }
    }

    $ParcompType = "Performance"
    $runParcompType = "Process"
    $CompressType = "All"
    $CompressTestPath = $ParcompOpts.CompressPathName
    $deCompressTestPath = $ParcompOpts.deCompressPathName
    $CNGTestPath = $CNGTestOpts.PathName

    # Run test
    if ($RunParcomp) {
        # Run parcomp exe
        $VMNameList | ForEach-Object {
            $PSSessionName = ("Session_{0}" -f $_)
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true

            Win-DebugTimestamp -output ("{0}: Start to compress test" -f $PSSessionName)
            $CompressTestResult = WBase-Parcomp -Side "remote" `
                                                -VMNameSuffix $_ `
                                                -deCompressFlag $false `
                                                -ParcompType $ParcompType `
                                                -runParcompType $runParcompType `
                                                -TestPathName $CompressTestPath

            Start-Sleep -Seconds 5

            Win-DebugTimestamp -output ("{0}: Start to decompress test" -f $PSSessionName)
            $deCompressTestResult = WBase-Parcomp -Side "remote" `
                                                  -VMNameSuffix $_ `
                                                  -deCompressFlag $true `
                                                  -ParcompType $ParcompType `
                                                  -runParcompType $runParcompType `
                                                  -TestPathName $deCompressTestPath

            Start-Sleep -Seconds 5
        }
    }

    if ($RunCNGtest) {
        # Run cngtest exe
        $VMNameList | ForEach-Object {
            $PSSessionName = ("Session_{0}" -f $_)
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true

            Win-DebugTimestamp -output ("{0}: Start to cng test" -f $PSSessionName)
            $CNGTestResult = WBase-CNGTest -Side "remote" `
                                           -VMNameSuffix $_ `
                                           -algo "rsa"
        }
    }

    # Get test result
    if ($RunParcomp) {
        # Get parcomp test result
        $VMNameList | ForEach-Object {
            $PSSessionName = ("Session_{0}" -f $_)
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true

            $CompressTestOutLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $CompressTestPath, $ParcompOpts.OutputLog
            $CompressTestErrorLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $CompressTestPath, $ParcompOpts.ErrorLog
            $deCompressTestOutLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $deCompressTestPath, $ParcompOpts.OutputLog
            $deCompressTestErrorLogPath = "{0}\\{1}\\{2}" -f $STVWinPath, $deCompressTestPath, $ParcompOpts.ErrorLog

            $StressTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    # Wait parcomp test process to complete
                    $WaitProcessFlag = WBase-WaitProcessToCompleted -ProcessName "parcomp" -Session $Session -Remote $true
                    if (!$WaitProcessFlag.result) {
                        $_.result = $WaitProcessFlag.result
                        $_.error = $WaitProcessFlag.error
                        return
                    }

                    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                        $CheckOutput = WBase-CheckOutput -TestOutputLog $CompressTestOutLogPath `
                                                         -TestErrorLog $CompressTestErrorLogPath `
                                                         -Session $Session `
                                                         -Remote $true `
                                                         -keyWords "Mbps"

                        if (!$CheckOutput.result) {
                            $_.result = $CheckOutput.result
                            $_.error = $CheckOutput.error
                            return
                        }
                    }

                    if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
                        $CheckOutput = WBase-CheckOutput -TestOutputLog $deCompressTestOutLogPath `
                                                         -TestErrorLog $deCompressTestErrorLogPath `
                                                         -Session $Session `
                                                         -Remote $true `
                                                         -keyWords "Mbps"

                        if (!$CheckOutput.result) {
                            $_.result = $CheckOutput.result
                            $_.error = $CheckOutput.error
                            return
                        }
                    }

                    if ($_.result) {
                        Win-DebugTimestamp -output ("{0}: The parcomp test ({1}) of stress is passed" -f $PSSessionName, $CompressType)
                        return
                    }
                }
            }
        }
    }

    if ($RunCNGtest) {
        # Get CNGTest test result
        $VMNameList | ForEach-Object {
            $PSSessionName = ("Session_{0}" -f $_)
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $Session = HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true

            $CNGTestOutLog = "{0}\\{1}\\{2}" -f $STVWinPath, $CNGTestPath, $CNGTestOpts.OutputLog
            $CNGTestErrorLog = "{0}\\{1}\\{2}" -f $STVWinPath, $CNGTestPath, $CNGTestOpts.ErrorLog

            $StressTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    # Wait cngtest test process to complete
                    $WaitProcessFlag = WBase-WaitProcessToCompleted -ProcessName "cngtest" -Session $Session -Remote $true
                    if (!$WaitProcessFlag.result) {
                        $_.result = $WaitProcessFlag.result
                        $_.error = $WaitProcessFlag.error
                        return
                    }

                    # Check cngtest test output log
                    $CheckOutput = WBase-CheckOutput -TestOutputLog $CNGTestOutLog `
                                                     -TestErrorLog $CNGTestErrorLog `
                                                     -Session $Session `
                                                     -Remote $true `
                                                     -keyWords "Ops/s"

                    $_.result = $CheckOutput.result
                    $_.error = $CheckOutput.error

                    if ($_.result) {
                        Win-DebugTimestamp -output ("{0}: The CNGtest of stress is passed" -f $PSSessionName)
                    }

                    return
                }
            }
        }
    }

    # Collate return value
    $testError = "|"
    $StressTestResultsList | ForEach-Object {
        if (!$_.parcomp) {
            $ReturnValue.result = $false
            $testError = "{0}{1}->parcomp->{2}|" -f $testError, $_.vm, $_.parcomperror
        }

        if (!$_.cng) {
            $ReturnValue.result = $false
            $testError = "{0}{1}->cngtest->{2}|" -f $testError, $_.vm, $_.cngerror
        }
    }

    if (!$ReturnValue.result) {
        $ReturnValue.error = $testError
    }

    return $ReturnValue
}


Export-ModuleMember -Function *-*
