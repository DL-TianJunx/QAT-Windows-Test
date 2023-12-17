
# About VMs
function WTW-RestartVMs
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [bool]$StopFlag = $true,

        [bool]$TurnOff = $true,

        [bool]$StartFlag = $true,

        [bool]$WaitFlag = $true
    )

    $VMName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
    if ($StopFlag) {
        HV-RestartVMHard `
            -VMName $VMName `
            -StopFlag $StopFlag `
            -TurnOff $TurnOff `
            -StartFlag $false `
            -WaitFlag $false | out-null
    }

    if ($WaitFlag -and $StopFlag) {
        Start-Sleep -Seconds 10
    }

    if ($StartFlag) {
        HV-RestartVMHard `
            -VMName $VMName `
            -StopFlag $false `
            -TurnOff $false `
            -StartFlag $StartFlag `
            -WaitFlag $false | out-null
    }

    if ($WaitFlag -and $StartFlag) {
        Start-Sleep -Seconds 30
    }
}

function WTW-RemoveVMs
{
    $VMList = Get-VM
    if (-not [String]::IsNullOrEmpty($VMList)) {
        Foreach ($VM in $VMList) {
            HV-RemoveVM -VMName $VM.Name | out-null
        }
    }
}

# About test ENV init
function WTW-ProcessVMInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [string]$VHDPath = $null,

        [string]$VHDName = $null
    )

    WBase-GetInfoFile | out-null

    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    # Create VMs
    if ([String]::IsNullOrEmpty($VHDPath)) {
        $VHDPath = $VHDAndTestFiles.ParentsVMPath
    }

    if ([String]::IsNullOrEmpty($VHDName)) {
        $VHDName = $LocationInfo.VM.ImageName
    }

    HV-CreateVM `
        -VMNameSuffix $VMNameSuffix `
        -VHDPath $VHDPath `
        -VHDName $VHDName | out-null

    # Start VMs
    WTW-RestartVMs `
        -VMNameSuffix $VMNameSuffix `
        -StopFlag $false `
        -TurnOff $false `
        -StartFlag $true `
        -WaitFlag $true | out-null

    $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix)
    $PSSessionName = ("Session_{0}" -f $VMNameSuffix)
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

        $ProcessPath = "{0}\\Process" -f $STVWinPath
        if (-not (Test-Path -Path $ProcessPath)) {
            New-Item -Path $ProcessPath -ItemType Directory
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
    $PDBDestinationPath = "C:\STV-tmp\TraceLog\PDB"
    Copy-Item `
        -ToSession $Session `
        -Path $PDBCopyPath `
        -Destination $PDBDestinationPath `
        -Include $PDBIncludeFiles `
        -Recurse `
        -Force `
        -Confirm:$false `
        -ErrorAction Stop | out-null

    $RestartVMFlag = $false
    # Check and set Test mode
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

    # Check and set Debug mode
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

    # Check and set driver verifier
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

    # ReStart VM if needed
    if ($RestartVMFlag) {
        # reStart VMs
        WTW-RestartVMs `
            -VMNameSuffix $VMNameSuffix ` `
            -StopFlag $true `
            -TurnOff $false `
            -StartFlag $true `
            -WaitFlag $true | out-null

        $Session = HV-PSSessionCreate `
            -VMName $VMName `
            -PSName $PSSessionName `
            -IsWin $true
    }

    # Run tracelog
    UT-TraceLogStart -Remote $true -Session $Session | out-null

    # Install qat cert
    UT-SetCertificate `
        -CertFile $Certificate.Remote `
        -Session $Session `
        -Remote $true

    Win-DebugTimestamp -output (
        "{0}: Install Qat driver on remote windows VM" -f $PSSessionName
    )

    # Install qat driver
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

    WBase-WaitProcessToCompletedByName `
        -ProcessName "QatSetup" `
        -Session $Session `
        -Remote $true | out-null

    # Double check QAT driver installed
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

    # Double check QAT devices work well
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

    # Check and set UQ mode
    $DisableDeviceFlag = $false
    $UQModeStatus = UT-CheckUQMode `
        -CheckFlag $LocationInfo.UQMode `
        -Remote $true `
        -Session $Session
    if (-not $UQModeStatus) {
        UT-SetUQMode `
            -UQMode $LocationInfo.UQMode `
            -Remote $true `
            -Session $Session | out-null

        UT-WorkAround `
            -Remote $true `
            -Session $Session `
            -DisableFlag $true | out-null
    }
}

function WTW-ENVInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMVFOSConfig,

        [bool]$InitVM = $true
    )

    HV-VMVFConfigInit -VMVFOSConfig $VMVFOSConfig | out-null

    WBase-GenerateInfoFile | out-null

    $VMNameList = $LocationInfo.VM.NameArray
    $ProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()

    if ($InitVM) {
        # Remove VMs
        WTW-RemoveVMs | out-null

        # Check VHD file for VMs
        $ParentsVM = "{0}\{1}.vhdx" -f
            $VHDAndTestFiles.ParentsVMPath,
            $LocationInfo.VM.ImageName
        if (-not [System.IO.File]::Exists($ParentsVM)) {
            Win-DebugTimestamp -output (
                "Copy Vhd file ({0}.vhdx) from remote {1}" -f
                    $LocationInfo.VM.ImageName,
                    $VHDAndTestFiles.SourceVMPath
            )

            $BertaSource = "{0}\\{1}.vhdx" -f
                $VHDAndTestFiles.SourceVMPath,
                $LocationInfo.VM.ImageName
            $BertaDestination = "{0}\\{1}.vhdx" -f
                $VHDAndTestFiles.ParentsVMPath,
                $LocationInfo.VM.ImageName

            Copy-Item `
                -Path $BertaSource `
                -Destination $BertaDestination `
                -Force `
                -ErrorAction Stop | out-null
        }

        # Start process of InitVM
        $VMNameList | ForEach-Object {
            $InitVMProcessArgs = "WTW-ProcessVMInit -VMNameSuffix {0}" -f $_
            $keyWords = "init_{0}" -f $_
            $InitVMProcess = WBase-StartProcess `
                -ProcessFilePath "pwsh" `
                -ProcessArgs $InitVMProcessArgs `
                -keyWords $keyWords

            $ProcessList[$_] = [hashtable] @{
                ID = $InitVMProcess.ID
                Output = $InitVMProcess.Output
                Error = $InitVMProcess.Error
                Result = $InitVMProcess.Result
            }

            $ProcessIDArray += $InitVMProcess.ID
        }

        # Check output and error log for InitVM process
        WBase-WaitProcessToCompletedByID `
            -ProcessID $ProcessIDArray `
            -Remote $false | out-null

        $VMNameList | ForEach-Object {
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            Win-DebugTimestamp -output ("Host: The output log of init {0} ----------------" -f $vmName)

            $ProcessResult = WBase-CheckProcessOutput `
                -ProcessOutputLog $ProcessList[$_].Output `
                -ProcessErrorLog $ProcessList[$_].Error `
                -CheckResultFlag $false `
                -Remote $false

            if ($ProcessResult.Result) {
                Win-DebugTimestamp -output ("Host: The init {0} is true" -f $vmName)
            } else {
                Win-DebugTimestamp -output ("Host: The init {0} is false" -f $vmName)
            }
        }

        # Re-create PS session
        $VMNameList | ForEach-Object {
            $PSSessionName = ("Session_{0}" -f $_)
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            HV-PSSessionCreate `
                -VMName $vmName `
                -PSName $PSSessionName `
                -IsWin $true `
                -CheckFlag $false | out-null
        }
    }
}

# About base test
function WTW-RemoteErrorHandle
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [Parameter(Mandatory=$True)]
        [hashtable]$TestResult,

        [Parameter(Mandatory=$True)]
        [string]$ParameterFileName,

        [bool]$Transfer = $false
    )

    $PSSessionName = "Session_{0}" -f $VMNameSuffix
    $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
    $Session = HV-PSSessionCreate `
        -VMName $vmName `
        -PSName $PSSessionName `
        -IsWin $true

    # Stop trace and transfer tracelog file
    UT-TraceLogStop -Remote $true -Session $Session | out-null
    if ($Transfer) {
        UT-TraceLogTransfer -Remote $true -Session $Session | out-null
    }

    # Handle:
    #    -process_timeout
    #    -BSOD_error
    #    -Copy tracelog file to 'BertaResultPath'
    if ($TestResult.error -eq "process_timeout") {
        Win-DebugTimestamp -output ("{0}: restart the VM because error > {1}" -f $PSSessionName, $TestResult.error)
        HV-RestartVMHard `
            -VMName $vmName `
            -StopFlag $true `
            -TurnOff $true `
            -StartFlag $true `
            -WaitFlag $true | out-null
    }

    if ($TestResult.error -eq "BSOD_error") {
        if (Invoke-Command -Session $Session -ScriptBlock {
                Param($SiteKeep)
                Test-Path -Path $SiteKeep.DumpFile
            } -ArgumentList $SiteKeep) {
            $Remote2HostDumpFile = "{0}\\Dump_{1}_{2}.DMP" -f
                $LocationInfo.BertaResultPath,
                $ParameterFileName,
                $VMNameSuffix
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

    Win-DebugTimestamp -output (
        "{0}: Copy tracelog etl files to '{1}'" -f $PSSessionName, $LocationInfo.BertaResultPath
    )
    $LocationInfo.PDBNameArray.Remote | ForEach-Object {
        $BertaEtlFile = "{0}\\Tracelog_{1}_{2}_{3}.etl" -f
            $LocationInfo.BertaResultPath,
            $_,
            $ParameterFileName,
            $VMNameSuffix
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

            if (Test-Path -Path $BertaEtlFile) {
                Win-DebugTimestamp -output ("{0}: Copy to {1}" -f $PSSessionName, $BertaEtlFile)
            }
        }
    }
}

# About SWFallback test
function WTW-EnableAndDisableQatDevice
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

function WTW-ChechFlagFile
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$FlagFileName
    )

    Win-DebugTimestamp -output ("Check flag file > {0}" -f $FlagFileName)

    $StopFlag = $true
    $TimeoutFlag = $false
    $TimeInterval = 3
    $WaitTime = 0
    $TimeOut = 900
    $FlagFilePath = "{0}\\{1}" -f $LocalProcessPath, $FlagFileName

    do {
        Start-Sleep -Seconds $TimeInterval
        $WaitTime += $TimeInterval
        if ($WaitTime -ge $TimeOut) {
            $TimeoutFlag = $true
            $StopFlag = $false
        } else {
            if (Test-Path -Path $FlagFilePath) {
                Win-DebugTimestamp -output ("Get flag file, stop wait")
                $StopFlag = $false
            }
        }
    } while ($StopFlag)

    if ($TimeoutFlag) {
        throw ("Can not get flag file, time out" )
    }
}

# Test: installer check
function WTW-ProcessInstaller
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [bool]$parcompFlag = $true,

        [bool]$cngtestFlag = $true
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
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

    WBase-GetInfoFile | out-null

    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    if ($TestType -eq "installer_files") {
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
    }

    $InstallerTestResultName = "ProcessResult_{0}.txt" -f $keyWords
    $InstallerTestResultPath = "{0}\\{1}" -f $LocalProcessPath, $InstallerTestResultName

    $PSSessionName = "Session_{0}" -f $VMNameSuffix
    $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
    $Session = HV-PSSessionCreate `
        -VMName $vmName `
        -PSName $PSSessionName `
        -IsWin $true `
        -CheckFlag $false

    # Run tracelog
    UT-TraceLogStart -Remote $true -Session $Session | out-null

    Win-DebugTimestamp -output (
        "{0}: Start to process of install test..." -f $PSSessionName
    )

    # Check qat driver
    $VMQatSetupPath = "{0}\\{1}\\{2}" -f
        $STVWinPath,
        $VMDriverInstallPath.InstallPath,
        $VMDriverInstallPath.QatSetupPath

    $CheckStatus = WBase-CheckDriverInstalled `
        -Remote $true `
        -Session $Session
    if (-not $CheckStatus) {
        WBase-InstallAndUninstallQatDriver `
            -Session $Session `
            -SetupExePath $VMQatSetupPath `
            -Operation $true `
            -Remote $true `
            -Wait $false `
            -UQMode $LocationInfo.UQMode | out-null

        WBase-WaitProcessToCompletedByName `
            -ProcessName "QatSetup" `
            -Session $Session `
            -Remote $true | out-null
    }

    Win-DebugTimestamp -output ("{0}: QAT driver installed" -f $PSSessionName)

    # Check qat driver files after install
    if ($TestType -eq "installer_files") {
        Foreach ($CheckType in $CheckTypes) {
            Win-DebugTimestamp -output (
                "{0}: After QAT driver installed, double check > {1}" -f
                    $PSSessionName,
                    $CheckType
            )

            $CheckStatus = WBase-CheckQatDriver `
                -Session $Session `
                -Type $CheckType `
                -Operation $true `
                -QatDriverServices $QatDriverServices `
                -QatDriverLibs $QatDriverLibs `
                -Remote $true

            if (-not $CheckStatus) {
                $ReturnValue.install[$CheckType].result = $CheckStatus
                $ReturnValue.install[$CheckType].error = "check_failed"
            }
        }
    }

    # Run simple test after install
    if ($parcompFlag) {
        Win-DebugTimestamp -output (
            "{0}: After QAT driver installed, run simple parcomp test" -f $PSSessionName
        )

        $ReturnValue.parcomp = WTW-SimpleParcomp -Session $Session
    }

    if ($cngtestFlag) {
        Win-DebugTimestamp -output (
            "{0}: After QAT driver installed, run simple CNGTest" -f $PSSessionName
        )

        $ReturnValue.cngtest = WTW-SimpleCNGTest -Session $Session
    }

    # Run static operation
    if ($TestType -eq "installer_static") {
        $OperationStatus = WBase-EnableAndDisableQatDevice `
            -Remote $true `
            -Session $Session `
            -Disable $true `
            -Enable $true `
            -Wait $true
        if (-not $OperationStatus) {
            $ReturnValue.disable.result = $OperationStatus
            $ReturnValue.disable.error = "disable_failed"
        }

        if ($parcompFlag) {
            Win-DebugTimestamp -output (
                "{0}: After disable and enable QAT devices, run simple parcomp test" -f $PSSessionName
            )

            if ($ReturnValue.parcomp.result) {
                $ReturnValue.parcomp = WTW-SimpleParcomp -Session $Session
            }
        }

        if ($cngtestFlag) {
            Win-DebugTimestamp -output (
                "{0}: After disable and enable QAT devices, run simple CNGTest" -f $PSSessionName
            )

            if ($ReturnValue.cngtest.result) {
                $ReturnValue.cngtest = WTW-SimpleCNGTest -Session $Session
            }
        }

        $ReturnValueWrite = $ReturnValue | ConvertTo-Json
        $ReturnValueWrite | Out-File $InstallerTestResultPath -Encoding ascii
    }

    if ($TestType -eq "installer_files") {
        # Uninstall QAT Windows driver
        Win-DebugTimestamp -output ("{0}: uninstall Qat driver" -f $PSSessionName)
        WBase-InstallAndUninstallQatDriver `
            -Session $Session `
            -SetupExePath $VMQatSetupPath `
            -Operation $false `
            -Remote $true `
            -Wait $false `
            -UQMode $LocationInfo.UQMode | out-null

        WBase-WaitProcessToCompletedByName `
            -ProcessName "QatSetup" `
            -Session $Session `
            -Remote $true | out-null

        # Check qat driver files after uninstall
        Foreach ($CheckType in $CheckTypes) {
            Win-DebugTimestamp -output (
                "{0}: After QAT driver uninstalled, double check > {1}" -f
                    $PSSessionName,
                    $CheckType
            )

            $CheckStatus = WBase-CheckQatDriver `
                -Session $Session `
                -Type $CheckType `
                -Operation $false `
                -QatDriverServices $QatDriverServices `
                -QatDriverLibs $QatDriverLibs `
                -Remote $true

            if (-not $CheckStatus) {
                $ReturnValue.uninstall[$CheckType].result = $CheckStatus
                $ReturnValue.uninstall[$CheckType].error = "check_failed"
            }
        }

        $ReturnValueWrite = $ReturnValue | ConvertTo-Json
        $ReturnValueWrite | Out-File $InstallerTestResultPath -Encoding ascii
    }

    $CheckStatus = WBase-CheckDriverInstalled `
        -Remote $true `
        -Session $Session
    if (-not $CheckStatus) {
        WBase-InstallAndUninstallQatDriver `
            -Session $Session `
            -SetupExePath $VMQatSetupPath `
            -Operation $true `
            -Remote $true `
            -Wait $false `
            -UQMode $LocationInfo.UQMode | out-null

        WBase-WaitProcessToCompletedByName `
            -ProcessName "QatSetup" `
            -Session $Session `
            -Remote $true | out-null
    }
}

function WTW-Installer
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [bool]$parcompFlag = $true,

        [bool]$cngtestFlag = $true
    )

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
    $InstallerProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()

    WBase-GenerateInfoFile | out-null

    # Run installer test as process
    $VMNameList | ForEach-Object {
        $PSSessionName = "Session_{0}" -f $_
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true `
            -CheckFlag $false

        $InstallerTestProcessArgs = "WTW-ProcessInstaller -VMNameSuffix {0}" -f $_
        $InstallerTestProcessArgs = "{0} -TestType {1}" -f $InstallerTestProcessArgs, $TestType
        $InstallerTestkeyWords = "installer_{0}" -f $_
        $InstallerTestProcessArgs = "{0} -keyWords {1}" -f $InstallerTestProcessArgs, $InstallerTestkeyWords

        if ($parcompFlag) {
            $InstallerTestProcessArgs = "{0} -parcompFlag 1" -f $InstallerTestProcessArgs
        } else {
            $InstallerTestProcessArgs = "{0} -parcompFlag 0" -f $InstallerTestProcessArgs
        }

        if ($cngtestFlag) {
            $InstallerTestProcessArgs = "{0} -cngtestFlag 1" -f $InstallerTestProcessArgs
        } else {
            $InstallerTestProcessArgs = "{0} -cngtestFlag 0" -f $InstallerTestProcessArgs
        }

        $InstallerTestProcess = WBase-StartProcess `
            -ProcessFilePath "pwsh" `
            -ProcessArgs $InstallerTestProcessArgs `
            -keyWords $InstallerTestkeyWords

        $InstallerProcessList[$_] = [hashtable] @{
            Output = $InstallerTestProcess.Output
            Error = $InstallerTestProcess.Error
            Result = $InstallerTestProcess.Result
        }

        $ProcessIDArray += $InstallerTestProcess.ID
    }

    # Check output and error log for installer process
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null

    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        Win-DebugTimestamp -output (
            "Host: The output log of installer process ---------------- {0}" -f $vmName
        )

        $InstallerTestResult = WBase-CheckProcessOutput `
            -ProcessOutputLog $InstallerProcessList[$_].Output `
            -ProcessErrorLog $InstallerProcessList[$_].Error `
            -ProcessResult $InstallerProcessList[$_].Result `
            -Remote $false

        if ($ReturnValue.install.service.result) {
            $ReturnValue.install.service.result = $InstallerTestResult.testResult.install.service.result
            $ReturnValue.install.service.error = $InstallerTestResult.testResult.install.service.error
        }

        if ($ReturnValue.install.device.result) {
            $ReturnValue.install.device.result = $InstallerTestResult.testResult.install.device.result
            $ReturnValue.install.device.error = $InstallerTestResult.testResult.install.device.error
        }

        if ($ReturnValue.install.library.result) {
            $ReturnValue.install.library.result = $InstallerTestResult.testResult.install.library.result
            $ReturnValue.install.library.error = $InstallerTestResult.testResult.install.library.error
        }

        if ($ReturnValue.uninstall.service.result) {
            $ReturnValue.uninstall.service.result = $InstallerTestResult.testResult.uninstall.service.result
            $ReturnValue.uninstall.service.error = $InstallerTestResult.testResult.uninstall.service.error
        }

        if ($ReturnValue.uninstall.device.result) {
            $ReturnValue.uninstall.device.result = $InstallerTestResult.testResult.uninstall.device.result
            $ReturnValue.uninstall.device.error = $InstallerTestResult.testResult.uninstall.device.error
        }

        if ($ReturnValue.uninstall.library.result) {
            $ReturnValue.uninstall.library.result = $InstallerTestResult.testResult.uninstall.library.result
            $ReturnValue.uninstall.library.error = $InstallerTestResult.testResult.uninstall.library.error
        }

        if ($ReturnValue.disable.result) {
            $ReturnValue.disable.result = $InstallerTestResult.testResult.disable.result
            $ReturnValue.disable.error = $InstallerTestResult.testResult.disable.error
        }

        if ($ReturnValue.parcomp.result) {
            $ReturnValue.parcomp.result = $InstallerTestResult.testResult.parcomp.result
            $ReturnValue.parcomp.error = $InstallerTestResult.testResult.parcomp.error
        }

        if ($ReturnValue.cngtest.result) {
            $ReturnValue.cngtest.result = $InstallerTestResult.testResult.cngtest.result
            $ReturnValue.cngtest.error = $InstallerTestResult.testResult.cngtest.error
        }

        if ($InstallerTestResult.result) {
            Win-DebugTimestamp -output ("Host: The installer test of {0} is true" -f $vmName)
        } else {
            Win-DebugTimestamp -output ("Host: The installer test of {0} is false" -f $vmName)
        }
    }

    return $ReturnValue
}

# Test: parcomp
function WTW-ProcessParcomp
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [Parameter(Mandatory=$True)]
        [string]$TestPath,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [bool]$CheckOutputFileFlag = $true,

        [bool]$deCompressFlag = $false,

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
        testOps = $null
    }

    WBase-GetInfoFile | out-null

    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    if (($TestType -eq "Base_Compat") -or ($TestType -eq "Base_Parameter")) {
        $ParcompType = "Base"
        $runParcompType = "Base"
    } elseif (($TestType -eq "Performance_Parameter") -or ($TestType -eq "Performance")) {
        $ParcompType = "Performance"
        $runParcompType = "Process"
    } elseif ($TestType -eq "Fallback") {
        $ParcompType = "Fallback"
        $runParcompType = "Process"
    }

    $ParcompTestOutLogPath = "{0}\\{1}" -f $TestPath, $ParcompOpts.OutputLog
    $ParcompTestErrorLogPath = "{0}\\{1}" -f $TestPath, $ParcompOpts.ErrorLog
    $ParcompTestResultName = "ProcessResult_{0}.json" -f $keyWords
    $ParcompTestResultPath = "{0}\\{1}" -f $LocalProcessPath, $ParcompTestResultName

    $PSSessionName = "Session_{0}" -f $VMNameSuffix
    $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
    $Session = HV-PSSessionCreate `
        -VMName $vmName `
        -PSName $PSSessionName `
        -IsWin $true `
        -CheckFlag $false

    # Run tracelog
    UT-TraceLogStart -Remote $true -Session $Session | out-null

    Win-DebugTimestamp -output (
        "{0}: Start to process of {1} test..." -f $PSSessionName, $TestType
    )

    # Run parcomp test
    $ParcompTestResult = WBase-Parcomp `
        -Remote $true `
        -Session $Session `
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
        -TestPath $TestPath `
        -TestFileType $TestFileType `
        -TestFileSize $TestFileSize

    Start-Sleep -Seconds 3

    # For Fallback test, wait operation completed
    if ($TestType -eq "Fallback") {
        WTW-ChechFlagFile -FlagFileName $OperationCompletedFlag | out-null
    }

    # Double check the output log
    if ($runParcompType -eq "Process") {
        # Wait parcomp test process
        $WaitStatus = WBase-WaitProcessToCompletedByID `
            -ProcessID $ParcompTestResult.process.ID `
            -Remote $true `
            -Session $Session
        if (-not $WaitStatus.result) {
            $ReturnValue.result = $WaitStatus.result
            $ReturnValue.error = $WaitStatus.error
        }

        Start-Sleep -Seconds 3

        # Check parcomp test result
        if ($ReturnValue.result) {
            $CheckOutput = WBase-CheckOutputLog `
                -TestOutputLog $ParcompTestOutLogPath `
                -TestErrorLog $ParcompTestErrorLogPath `
                -Session $Session `
                -Remote $true `
                -keyWords "Mbps"
            if (-not $CheckOutput.result) {
                $ReturnValue.result = $CheckOutput.result
                $ReturnValue.error = $CheckOutput.error
                $ReturnValue.testOps = $CheckOutput.testOps
            }
        }
    } else {
        $ReturnValue.result = $ParcompTestResult.result
        $ReturnValue.error = $ParcompTestResult.error
        $ReturnValue.testOps = $ParcompTestResult.testOps
    }

    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $ParcompTestResultPath | out-null

    # Double check the output files
    if (($CheckOutputFileFlag) -and ($ReturnValue.result)) {
        Win-DebugTimestamp -output ("{0}: Double check the output files" -f $PSSessionName)

        $CheckMD5Result = WBase-CheckOutputFile `
            -Remote $true `
            -Session $Session `
            -deCompressFlag $deCompressFlag `
            -CompressProvider $CompressProvider `
            -deCompressProvider $deCompressProvider `
            -QatCompressionType $QatCompressionType `
            -Level $Level `
            -Chunk $Chunk `
            -blockSize $blockSize `
            -TestFileType $TestFileType `
            -TestFileSize $TestFileSize `
            -TestPath $TestPath

        if (-not $CheckMD5Result.result) {
            $ReturnValue.result = $CheckMD5Result.result
            $ReturnValue.error = $CheckMD5Result.error

            WBase-WriteHashtableToJsonFile `
                -Info $ReturnValue `
                -InfoFilePath $ParcompTestResultPath | out-null
        }
    }

    # After parcomp fallback test, run simple parcomp test
    if (($TestType -eq "Fallback") -and ($ReturnValue.result)) {
        Win-DebugTimestamp -output (
            "{0}: After parcomp fallback test, run simple parcomp test" -f $PSSessionName
        )

        $ParcompTestResult = WTW-SimpleParcomp -Session $Session
        if (-not $ParcompTestResult.result) {
            $ReturnValue.result = $ParcompTestResult.result
            $ReturnValue.error = $ParcompTestResult.error

            WBase-WriteHashtableToJsonFile `
                -Info $ReturnValue `
                -InfoFilePath $ParcompTestResultPath | out-null
        }
    }

    # Handle all error
    if (-not $ReturnValue.result) {
        WTW-RemoteErrorHandle `
            -VMNameSuffix $VMNameSuffix `
            -TestResult $ReturnValue `
            -ParameterFileName $LocationInfo.TestCaseName | out-null
    }
}

function WTW-SimpleParcomp
{
    Param(
        [Parameter(Mandatory=$True)]
        [object]$Session
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = $null
    }

    $ParcompTestResult = WBase-Parcomp `
        -Remote $true `
        -Session $Session `
        -deCompressFlag $false `
        -CompressProvider "qat" `
        -deCompressProvider "qat" `
        -QatCompressionType "dynamic" `
        -Level 1 `
        -Chunk 64 `
        -blockSize 4096 `
        -numThreads 1 `
        -numIterations 1

    $ReturnValue.result = $ParcompTestResult.result
    $ReturnValue.error = $ParcompTestResult.error
    $ReturnValue.testOps = $ParcompTestResult.testOps

    return $ReturnValue
}

function WTW-Parcomp
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [bool]$deCompressFlag = $false,

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$Chunk = 64,

        [int]$blockSize = 4096,

        [int]$numThreads = 6,

        [int]$numIterations = 200,

        [string]$TestPath = $null,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200,

        [string]$TestOperationType = $null,

        [string]$CompressType = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = $null
    }

    $VMNameList = $LocationInfo.VM.NameArray
    $CompressProcessList = [hashtable] @{}
    $deCompressProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()
    $TestSourceFile = "{0}\\{1}{2}.txt" -f $STVWinPath, $TestFileType, $TestFileSize

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.PathName
    }

    WBase-GenerateInfoFile | out-null

    $OperationCompletedFlagPath = "{0}\\{1}" -f
        $LocalProcessPath,
        $OperationCompletedFlag
    if (Test-Path -Path $OperationCompletedFlagPath) {
        Get-Item -Path $OperationCompletedFlagPath | Remove-Item -Recurse -Force
    }

    # Run parcomp test as process
    $VMNameList | ForEach-Object {
        $PSSessionName = "Session_{0}" -f $_
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true `
            -CheckFlag $false

        $ParcompProcessArgs = "WTW-ProcessParcomp -VMNameSuffix {0}" -f $_
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
        $ParcompProcessArgs = "{0} -TestType {1}" -f $ParcompProcessArgs, $TestType

        if ($TestType -eq "Performance") {
            $ParcompProcessArgs = "{0} -CheckOutputFileFlag 0" -f $ParcompProcessArgs
        } else {
            $ParcompProcessArgs = "{0} -CheckOutputFileFlag 1" -f $ParcompProcessArgs
        }

        if (($CompressType -eq "Compress") -or ($CompressType -eq "All") -or !$deCompressFlag) {
            if ($TestType -eq "Fallback") {
                $CompressTestPathName = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.CompressPathName
            } else {
                $CompressTestPathName = $TestPath
            }

            $CompressProcessArgs = "{0} -TestPath {1}" -f $ParcompProcessArgs, $CompressTestPathName
            $CompressProcessArgs = "{0} -deCompressFlag 0" -f $CompressProcessArgs
            $CompresskeyWords = "Compress_{0}" -f $_
            $CompressProcessArgs = "{0} -keyWords {1}" -f $CompressProcessArgs, $CompresskeyWords

            $CompressProcess = WBase-StartProcess `
                -ProcessFilePath "pwsh" `
                -ProcessArgs $CompressProcessArgs `
                -keyWords $CompresskeyWords

            $CompressProcessList[$_] = [hashtable] @{
                Output = $CompressProcess.Output
                Error = $CompressProcess.Error
                Result = $CompressProcess.Result
            }

            $ProcessIDArray += $CompressProcess.ID
        }

        if (($CompressType -eq "deCompress") -or ($CompressType -eq "All") -or $deCompressFlag) {
            if ($TestType -eq "Fallback") {
                $deCompressTestPathName = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.deCompressPathName
            } else {
                $deCompressTestPathName = $TestPath
            }

            $deCompressProcessArgs = "{0} -TestPath {1}" -f $ParcompProcessArgs, $deCompressTestPathName
            $deCompressProcessArgs = "{0} -deCompressFlag 1" -f $deCompressProcessArgs
            $deCompresskeyWords = "deCompress_{0}" -f $_
            $deCompressProcessArgs = "{0} -keyWords {1}" -f $deCompressProcessArgs, $deCompresskeyWords

            $deCompressProcess = WBase-StartProcess `
                -ProcessFilePath "pwsh" `
                -ProcessArgs $deCompressProcessArgs `
                -keyWords $deCompresskeyWords

            $deCompressProcessList[$_] = [hashtable] @{
                Output = $deCompressProcess.Output
                Error = $deCompressProcess.Error
                Result = $deCompressProcess.Result
            }

            $ProcessIDArray += $deCompressProcess.ID
        }
    }

    # Run operation
    if ($TestType -eq "Fallback") {
        Start-Sleep -Seconds 10

        # Operation: heartbeat, disable, upgrade
        if ($TestOperationType -eq "heartbeat") {
            Win-DebugTimestamp -output ("Run 'heartbeat' operation on local host")
            $heartbeatStatus = WBase-HeartbeatQatDevice -LogPath $LocationInfo.BertaResultPath

            Win-DebugTimestamp -output ("The heartbeat operation > {0}" -f $heartbeatStatus)
            if (!$heartbeatStatus) {
                $ReturnValue.result = $heartbeatStatus
                $ReturnValue.error = "heartbeat_failed"
            }
        } elseif ($TestOperationType -eq "disable") {
            Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on VMs")
            $disableStatus = WTW-EnableAndDisableQatDevice -VMNameList $VMNameList

            Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
            if (!$disableStatus) {
                $ReturnValue.result = $disableStatus
                $ReturnValue.error = "disable_failed"
            }
        } elseif ($TestOperationType -eq "upgrade") {
            Win-DebugTimestamp -output ("Run 'upgrade' operation on local host")
            $upgradeStatus = WBase-UpgradeQatDevice

            Win-DebugTimestamp -output ("The upgrade operation > {0}" -f $upgradeStatus)
            if (!$upgradeStatus) {
                $ReturnValue.result = $upgradeStatus
                $ReturnValue.error = "upgrade_failed"
            }
        } else {
            Win-DebugTimestamp -output ("The fallback test does not support Operation type > {0}" -f $TestOperationType)
            $ReturnValue.result = $false
            $ReturnValue.error = ("operation_type_{0}" -f $TestOperationType)
        }

        if (-not (Test-Path -Path $OperationCompletedFlagPath)) {
            New-Item -Path $LocalProcessPath -Name $OperationCompletedFlag -ItemType "file" | out-null
        }
    }

    # Check output and error log for parcomp process
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null

    $TotalOps = 0
    $VMNameList | ForEach-Object {
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
        Win-DebugTimestamp -output (
            "Host: The output log of parcomp process ---------------- {0}" -f $vmName
        )

        if (($CompressType -eq "Compress") -or ($CompressType -eq "All") -or !$deCompressFlag) {
            $CompressResult = WBase-CheckProcessOutput `
                -ProcessOutputLog $CompressProcessList[$_].Output `
                -ProcessErrorLog $CompressProcessList[$_].Error `
                -ProcessResult $CompressProcessList[$_].Result `
                -Remote $false

            $TotalOps += $CompressResult.testResult.testOps
            if ($ReturnValue.result) {
                $ReturnValue.result = $CompressResult.result
                $ReturnValue.error = $CompressResult.error
            }

            if ($CompressResult.result) {
                Win-DebugTimestamp -output ("Host: The compress parcomp test of {0} is true" -f $vmName)
            } else {
                Win-DebugTimestamp -output ("Host: The compress parcomp test of {0} is false" -f $vmName)
            }
        }

        if (($CompressType -eq "deCompress") -or ($CompressType -eq "All") -or $deCompressFlag) {
            $deCompressResult = WBase-CheckProcessOutput `
                -ProcessOutputLog $deCompressProcessList[$_].Output `
                -ProcessErrorLog $deCompressProcessList[$_].Error `
                -ProcessResult $deCompressProcessList[$_].Result `
                -Remote $false

            $TotalOps += $deCompressResult.testResult.testOps
            if ($ReturnValue.result) {
                $ReturnValue.result = $deCompressResult.result
                $ReturnValue.error = $deCompressResult.error
            }

            if ($deCompressResult.result) {
                Win-DebugTimestamp -output ("Host: The decompress parcomp test of {0} is true" -f $vmName)
            } else {
                Win-DebugTimestamp -output ("Host: The decompress parcomp test of {0} is false" -f $vmName)
            }
        }
    }

    $ReturnValue.testOps = [int]($TotalOps / $VMNameList.length)

    return $ReturnValue
}

# Test: cngtest
function WTW-ProcessCNGTest
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$VMNameSuffix,

        [Parameter(Mandatory=$True)]
        [string]$TestPath,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [Parameter(Mandatory=$True)]
        [string]$algo,

        [string]$operation = "encrypt",

        [string]$provider = "qa",

        [int]$keyLength = 2048,

        [string]$ecccurve = "nistP256",

        [string]$padding = "pkcs1",

        [string]$numThreads = 96,

        [string]$numIter = 10000
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = $null
    }

    WBase-GetInfoFile | out-null

    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog
    $CNGTestResultName = "ProcessResult_{0}.json" -f $keyWords
    $CNGTestResultPath = "{0}\\{1}" -f $LocalProcessPath, $CNGTestResultName

    $PSSessionName = "Session_{0}" -f $VMNameSuffix
    $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
    $Session = HV-PSSessionCreate `
        -VMName $vmName `
        -PSName $PSSessionName `
        -IsWin $true `
        -CheckFlag $false

    # Run tracelog
    UT-TraceLogStart -Remote $true -Session $Session | out-null

    Win-DebugTimestamp -output (
        "{0}: Start to process of {1} test..." -f $PSSessionName, $TestType
    )

    # Run cngtest
    $CNGTestResult = WBase-CNGTest `
        -Remote $true `
        -Session $Session `
        -algo $algo `
        -operation $operation `
        -provider $provider `
        -keyLength $keyLength `
        -ecccurve $ecccurve `
        -padding $padding `
        -numThreads $numThreads `
        -numIter $numIter `
        -TestPath $TestPath

    # For Fallback test, wait operation completed
    if ($TestType -eq "Fallback") {
        WTW-ChechFlagFile -FlagFileName $OperationCompletedFlag | out-null
    }

    # Wait parcomp test process
    $WaitStatus = WBase-WaitProcessToCompletedByID `
        -ProcessID $CNGTestResult.process.ID `
        -Remote $true `
        -Session $Session
    if (-not $WaitStatus.result) {
        $ReturnValue.result = $WaitStatus.result
        $ReturnValue.error = $WaitStatus.error
    }

    Start-Sleep -Seconds 3

    # Double check the output log
    if ($ReturnValue.result) {
        $CheckOutput = WBase-CheckOutputLog `
            -TestOutputLog $CNGTestOutLog `
            -TestErrorLog $CNGTestErrorLog `
            -Session $Session `
            -Remote $true `
            -keyWords "Ops/s"

        $ReturnValue.result = $CheckOutput.result
        $ReturnValue.error = $CheckOutput.error
        $ReturnValue.testOps = $CheckOutput.testOps
    }

    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $CNGTestResultPath | out-null

    # After fallback cngtest, run simple cngtest
    if (($TestType -eq "Fallback") -and ($ReturnValue.result)) {
        Win-DebugTimestamp -output (
            "{0}: After fallback cngtest, run simple cngtest" -f $PSSessionName
        )

        $CNGTestResult = WTW-SimpleCNGTest -Session $Session
        $ReturnValue.result = $CNGTestResult.result
        $ReturnValue.error = $CNGTestResult.error
    }

    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $CNGTestResultPath | out-null

    # Handle all error
    if (-not $ReturnValue.result) {
        WTW-RemoteErrorHandle `
            -VMNameSuffix $VMNameSuffix `
            -TestResult $ReturnValue `
            -ParameterFileName $LocationInfo.TestCaseName | out-null
    }
}

function WTW-SimpleCNGTest
{
    Param(
        [Parameter(Mandatory=$True)]
        [object]$Session
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = $null
    }

    $CNGTestResult = WBase-CNGTest `
        -Remote $true `
        -Session $Session `
        -algo "rsa" `
        -operation "encrypt" `
        -provider "qa" `
        -keyLength 2048 `
        -ecccurve "nistP256" `
        -padding "pkcs1" `
        -numThreads 8 `
        -numIter 10

    WBase-WaitProcessToCompletedByID `
        -ProcessID $CNGTestResult.process.ID `
        -Remote $true `
        -Session $Session | out-null

    $CNGTestOutLog = "{0}\\{1}\\{2}" -f
        $STVWinPath,
        $CNGTestOpts.PathName,
        $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}\\{2}" -f
        $STVWinPath,
        $CNGTestOpts.PathName,
        $CNGTestOpts.ErrorLog
    $CheckOutput = WBase-CheckOutputLog `
        -TestOutputLog $CNGTestOutLog `
        -TestErrorLog $CNGTestErrorLog `
        -Session $Session `
        -Remote $true `
        -keyWords "Ops/s"

    $ReturnValue.result = $CheckOutput.result
    $ReturnValue.error = $CheckOutput.error

    return $ReturnValue
}

function WTW-CNGTest
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [Parameter(Mandatory=$True)]
        [string]$algo,

        [string]$operation = "encrypt",

        [string]$provider = "qa",

        [int]$keyLength = 2048,

        [string]$ecccurve = "nistP256",

        [string]$padding = "pkcs1",

        [string]$numThreads = 96,

        [string]$numIter = 10000,

        [string]$TestPath = $null,

        [string]$TestOperationType = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = $null
    }

    $VMNameList = $LocationInfo.VM.NameArray
    $CNGTestProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $CNGTestOpts.PathName
    }

    WBase-GenerateInfoFile | out-null

    $OperationCompletedFlagPath = "{0}\\{1}" -f
        $LocalProcessPath,
        $OperationCompletedFlag
    if (Test-Path -Path $OperationCompletedFlagPath) {
        Get-Item -Path $OperationCompletedFlagPath | Remove-Item -Recurse -Force
    }

    # Run cngtest as process
    $VMNameList | ForEach-Object {
        $PSSessionName = "Session_{0}" -f $_
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $_
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true `
            -CheckFlag $false

        $CNGTestProcessArgs = "WTW-ProcessCNGTest -VMNameSuffix {0}" -f $_
        $CNGTestProcessArgs = "{0} -algo {1}" -f $CNGTestProcessArgs, $algo
        $CNGTestProcessArgs = "{0} -operation {1}" -f $CNGTestProcessArgs, $operation
        $CNGTestProcessArgs = "{0} -provider {1}" -f $CNGTestProcessArgs, $provider
        $CNGTestProcessArgs = "{0} -keyLength {1}" -f $CNGTestProcessArgs, $keyLength
        $CNGTestProcessArgs = "{0} -ecccurve {1}" -f $CNGTestProcessArgs, $ecccurve
        $CNGTestProcessArgs = "{0} -padding {1}" -f $CNGTestProcessArgs, $padding
        $CNGTestProcessArgs = "{0} -numThreads {1}" -f $CNGTestProcessArgs, $numThreads
        $CNGTestProcessArgs = "{0} -numIter {1}" -f $CNGTestProcessArgs, $numIter
        $CNGTestProcessArgs = "{0} -TestPath {1}" -f $CNGTestProcessArgs, $TestPath
        $CNGTestProcessArgs = "{0} -TestType {1}" -f $CNGTestProcessArgs, $TestType
        $CNGTestkeyWords = "{0}_{1}" -f $operation, $_
        $CNGTestProcessArgs = "{0} -keyWords {1}" -f $CNGTestProcessArgs, $CNGTestkeyWords

        $CNGTestProcess = WBase-StartProcess `
            -ProcessFilePath "pwsh" `
            -ProcessArgs $CNGTestProcessArgs `
            -keyWords $CNGTestkeyWords

        $CNGTestProcessList[$_] = [hashtable] @{
            Output = $CNGTestProcess.Output
            Error = $CNGTestProcess.Error
            Result = $CNGTestProcess.Result
        }

        $ProcessIDArray += $CNGTestProcess.ID
    }

    # Operation: heartbeat, disable, upgrade
    if ($TestType -eq "Fallback") {
        Start-Sleep -Seconds 10

        if ($TestOperationType -eq "heartbeat") {
            Win-DebugTimestamp -output ("Run 'heartbeat' operation on local host")
            $heartbeatStatus = WBase-HeartbeatQatDevice -LogPath $LocationInfo.BertaResultPath

            Win-DebugTimestamp -output ("The heartbeat operation > {0}" -f $heartbeatStatus)
            if (!$heartbeatStatus) {
                $ReturnValue.result = $heartbeatStatus
                $ReturnValue.error = "heartbeat_failed"
            }
        } elseif ($TestOperationType -eq "disable") {
            Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on VMs")
            $disableStatus = WTW-EnableAndDisableQatDevice -VMNameList $VMNameList

            Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
            if (!$disableStatus) {
                $ReturnValue.result = $disableStatus
                $ReturnValue.error = "disable_failed"
            }
        } elseif ($TestOperationType -eq "upgrade") {
            Win-DebugTimestamp -output ("Run 'upgrade' operation on local host")
            $upgradeStatus = WBase-UpgradeQatDevice

            Win-DebugTimestamp -output ("The upgrade operation > {0}" -f $upgradeStatus)
            if (!$upgradeStatus) {
                $ReturnValue.result = $upgradeStatus
                $ReturnValue.error = "upgrade_failed"
            }
        } else {
            Win-DebugTimestamp -output ("The fallback test does not support Operation type > {0}" -f $TestOperationType)
            $ReturnValue.result = $false
            $ReturnValue.error = ("operation_type_{0}" -f $TestOperationType)
        }

        if (-not (Test-Path -Path $OperationCompletedFlagPath)) {
            New-Item -Path $LocalProcessPath -Name $OperationCompletedFlag -ItemType "file" | out-null
        }
    }

    # Check output and error log for cngtest process
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null

    $TotalOps = 0
    $VMNameList | ForEach-Object {
        $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
        Win-DebugTimestamp -output (
            "Host: The output log of CNGTest process ---------------- {0}" -f $vmName
        )

        $CNGTestResult = WBase-CheckProcessOutput `
            -ProcessOutputLog $CNGTestProcessList[$_].Output `
            -ProcessErrorLog $CNGTestProcessList[$_].Error `
            -ProcessResult $CNGTestProcessList[$_].Result `
            -Remote $false

        $TotalOps += $CNGTestResult.testResult.testOps
        if ($ReturnValue.result) {
            $ReturnValue.result = $CNGTestResult.result
            $ReturnValue.error = $CNGTestResult.error
        }

        if ($CNGTestResult.result) {
            Win-DebugTimestamp -output ("Host: The CNGTest of {0} is true" -f $vmName)
        } else {
            Win-DebugTimestamp -output ("Host: The CNGTest of {0} is false" -f $vmName)
        }
    }

    $ReturnValue.testOps = [int]($TotalOps / $VMNameList.length)

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
    $CompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.CompressPathName
    $deCompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.deCompressPathName
    $CNGTestPath = "{0}\\{1}" -f $STVWinPath, $CNGTestOpts.PathName

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
            $CompressTestResult = WBase-Parcomp `
                -Remote $true `
                -Session $Session `
                -deCompressFlag $false `
                -ParcompType $ParcompType `
                -runParcompType $runParcompType `
                -TestPath $CompressTestPath

            Start-Sleep -Seconds 5

            Win-DebugTimestamp -output ("{0}: Start to decompress test" -f $PSSessionName)
            $deCompressTestResult = WBase-Parcomp `
                -Remote $true `
                -Session $Session `
                -deCompressFlag $true `
                -ParcompType $ParcompType `
                -runParcompType $runParcompType `
                -TestPath $deCompressTestPath

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
            $CNGTestResult = WBase-CNGTest -Remote $true `
                                           -Session $Session `
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

            $CompressTestOutLogPath = "{0}\\{1}" -f $CompressTestPath, $ParcompOpts.OutputLog
            $CompressTestErrorLogPath = "{0}\\{1}" -f $CompressTestPath, $ParcompOpts.ErrorLog
            $deCompressTestOutLogPath = "{0}\\{1}" -f $deCompressTestPath, $ParcompOpts.OutputLog
            $deCompressTestErrorLogPath = "{0}\\{1}" -f $deCompressTestPath, $ParcompOpts.ErrorLog

            $StressTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    # Wait parcomp test process to complete
                    $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "parcomp" -Session $Session -Remote $true
                    if (!$WaitProcessFlag.result) {
                        $_.result = $WaitProcessFlag.result
                        $_.error = $WaitProcessFlag.error
                        return
                    }

                    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                        $CheckOutput = WBase-CheckOutputLog `
                            -TestOutputLog $CompressTestOutLogPath `
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
                        $CheckOutput = WBase-CheckOutputLog `
                            -TestOutputLog $deCompressTestOutLogPath `
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

            $CNGTestOutLog = "{0}\\{1}" -f $CNGTestPath, $CNGTestOpts.OutputLog
            $CNGTestErrorLog = "{0}\\{1}" -f $CNGTestPath, $CNGTestOpts.ErrorLog

            $StressTestResultsList | ForEach-Object {
                if ($_.vm -eq $vmName) {
                    # Wait cngtest test process to complete
                    $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "cngtest" -Session $Session -Remote $true
                    if (!$WaitProcessFlag.result) {
                        $_.result = $WaitProcessFlag.result
                        $_.error = $WaitProcessFlag.error
                        return
                    }

                    # Check cngtest test output log
                    $CheckOutput = WBase-CheckOutputLog `
                        -TestOutputLog $CNGTestOutLog `
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
