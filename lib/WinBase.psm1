# Global Variables
if (!$QATTESTPATH) {
    $TestSuitePath = Split-Path -Parent (Split-Path -Path $PSCommandPath)
    Set-Variable -Name "QATTESTPATH" -Value $TestSuitePath -Scope global
}

Import-Module "$QATTESTPATH\\lib\\GlobalVariable.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\HyperV.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\UtilTools.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\BertaTools.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\Win2Linux.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\Win2Win.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\WinHost.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\Domain.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\GTest.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\FIPS.psm1" -Force -DisableNameChecking

# About Init
function Win-DebugTimestamp
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$output,

        [bool]$WriteLogToConsole = $false,

        [bool]$WriteLogToFile = $false,

        [string]$WriteLogFilePath = $null
    )

    if ([String]::IsNullOrEmpty($WriteLogFilePath)) {
        $WriteLogFilePath = $WinPowerShellLogFile
    }

    if (-not $WriteLogToConsole) {$WriteLogToConsole = $LocationInfo.WriteLogToConsole}
    if (-not $WriteLogToFile) {$WriteLogToFile = $LocationInfo.WriteLogToFile}

    $CallStack = Get-PSCallStack
    if ($CallStack.Count -gt 1) {
        if ($LocationInfo.HVMode) {
            $PowershellLog = ("{0}, {1}: {2}" -f (Get-Date -Format 'yyyy:MM:dd:hh:mm:ss:fff'), $CallStack[2].FunctionName, $output)
        } else {
            $PowershellLog = ("{0}, {1}: {2}" -f (Get-Date -Format 'yyyy:MM:dd:hh:mm:ss:fff'), $CallStack[1].FunctionName, $output)
        }
    } else {
        $PowershellLog = ("{0}: {1}" -f (Get-Date -Format 'yyyy:MM:dd:hh:mm:ss:fff'), $output)
    }

    if ($WriteLogToConsole) {
        Write-Host ($PowershellLog)
    }

    if ($WriteLogToFile) {
        $PowershellLog | Out-File $WriteLogFilePath -Append -Encoding ascii
    }
}

function WBase-ReturnFilesInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$BertaResultPath,

        [Parameter(Mandatory=$True)]
        [string]$ResultFile
    )

    Set-Variable -Name "WinPowerShellLogFile" -Value ("{0}\\STVTest-ps.log" -f $BertaResultPath) -Scope global
    Set-Variable -Name "WinTestResultFile" -Value ("{0}\\{1}" -f $BertaResultPath, $ResultFile) -Scope global
    Set-Variable -Name "WinTestResultCsv" -Value ("{0}\\result.csv" -f $BertaResultPath) -Scope global
    Set-Variable -Name "WinTestProcessPath" -Value ("{0}\\Process" -f $BertaResultPath) -Scope global
    $LocationInfo.WriteLogToFile = $true

    if (Test-Path -Path $WinPowerShellLogFile) {
        $WinPSLogFilePath = Split-Path -Path $WinPowerShellLogFile
        $WinPSLogFileName = Split-Path -Path $WinPowerShellLogFile -Leaf
        $WinPSLogFileNameArray = $WinPSLogFileName.split(".")
        for ($i = 0; $i -lt 1000; $i++) {
            $WinPSLogFile = "{0}{1}-{2}.{3}" -f
                $WinPSLogFilePath,
                $WinPSLogFileNameArray[0],
                $i,
                $WinPSLogFileNameArray[1]
            if (-not (Test-Path -Path $WinPSLogFile)) {
                break
            }
        }
        Copy-Item -Path $WinPowerShellLogFile -Destination $WinPSLogFile
        Get-Item -Path $WinPowerShellLogFile | Remove-Item -Recurse
    }
    New-Item -Path $BertaResultPath -Name "STVTest-ps.log" -ItemType "file" | out-null

    if (Test-Path -Path $WinTestResultFile) {
        $WinResultFilePath = Split-Path -Path $WinTestResultFile
        $WinResultFileName = Split-Path -Path $WinTestResultFile -Leaf
        $WinResultFileNameArray = $WinResultFileName.split(".")
        for ($i = 0; $i -lt 1000; $i++) {
            $WinResultFile = "{0}{1}-{2}.{3}" -f
                $WinResultFilePath,
                $WinResultFileNameArray[0],
                $i,
                $WinResultFileNameArray[1]
            if (-not (Test-Path -Path $WinResultFile)) {
                break
            }
        }
        Copy-Item -Path $WinTestResultFile -Destination $WinResultFile
        Get-Item -Path $WinTestResultFile | Remove-Item -Recurse
    }
    New-Item -Path $BertaResultPath -Name $ResultFile -ItemType "file" | out-null

    if (Test-Path -Path $WinTestResultCsv) {
        $WinResultCsvPath = Split-Path -Path $WinTestResultCsv
        $WinResultCsvName = Split-Path -Path $WinTestResultCsv -Leaf
        $WinResultCsvNameArray = $WinResultCsvName.split(".")
        for ($i = 0; $i -lt 1000; $i++) {
            $WinResultCsv = "{0}{1}-{2}.{3}" -f
                $WinResultCsvPath,
                $WinResultCsvNameArray[0],
                $i,
                $WinResultCsvNameArray[1]
            if (-not (Test-Path -Path $WinResultCsv)) {
                break
            }
        }
        Copy-Item -Path $WinTestResultCsv -Destination $WinResultCsv
        Get-Item -Path $WinTestResultCsv | Remove-Item -Recurse
    }
    New-Item -Path $BertaResultPath -Name "result.csv" -ItemType "file" | out-null

    if (-not (Test-Path -Path $WinTestProcessPath)) {
        New-Item -Path $WinTestProcessPath -ItemType Directory | out-null
    }
}

function WBase-WriteTestResult
{
    Param(
        [Parameter(Mandatory=$True)]
        [hashtable]$TestResult,

        [string]$ResultFile = $null,

        [bool]$WriteFlag = $true
    )

    if ([String]::IsNullOrEmpty($ResultFile)) {
        $ResultFile = $WinTestResultFile
    }

    # do ToUpper here to cover both param sets
    if ("s" -in $TestResult.keys) {$TestResult.s = $TestResult.s.ToUpper()}
    $resultJson = $TestResult | ConvertTo-Json
    $resultJson = $resultJson -replace "\n", ""
    $resultJson = $resultJson -replace "\s+", " "
    $resultJson | Out-File $ResultFile -Append -Encoding ascii

    if ($ResultFile -eq $WinTestResultFile) {
        if ($WriteFlag) {
            Win-DebugTimestamp -output ("{0} > {1}" -f $ResultFile, $resultJson)
            Win-DebugTimestamp -output ("-------------------------------------------------------------------------------------------------")
        }
    }
}

function WBase-WriteResultCsv
{
    Param(
         [Parameter(Mandatory=$True)]
         [string]$ReadMessagePath
    )

    if (-not ([String]::IsNullOrEmpty($ReadMessagePath))) {
        $ReadResult = Get-Content -Path $ReadMessagePath
        if ([int]$ReadResult.length -ne 0){
            $CaseNumber = 1
            $ReadResult | ForEach {
                $JasonTest = ConvertFrom-Json -InputObject $_ -AsHashtable
                $HandelTestCase = $JasonTest.tc
                $HandelTestResult = $JasonTest.s
                [PsCustomObject]@{
                   TestNumber = $CaseNumber
                   TestCase = $HandelTestCase
                   TestResult = $HandelTestResult
                }
                $CaseNumber = $CaseNumber + 1
            } | Export-Csv -Path $WinTestResultCsv -NoTypeInformation
        }
    }
}

function WBase-CompareTestResult
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$CompareFile
    )

    if ((Test-Path -Path $WinTestResultFile) -and
        (Test-Path -Path $CompareFile)) {
        $WinTestResult = Get-Content -Path $WinTestResultFile
        $CompareTestResult = Get-Content -Path $CompareFile

        ForEach ($CompareLine in $CompareTestResult) {
            $CompareLine = ConvertFrom-Json -InputObject $CompareLine -AsHashtable
            $writeFlag = $true

            ForEach ($WinLine in $WinTestResult) {
                $WinLine = ConvertFrom-Json -InputObject $WinLine -AsHashtable

                if ($CompareLine.tc -eq $WinLine.tc) {
                    $writeFlag = $false
                }
            }

            if ($writeFlag) {
                WBase-WriteTestResult -TestResult $CompareLine -WriteFlag $false
            }
        }

        # Generate result.csv file
        WBase-WriteResultCsv -ReadMessagePath $WinTestResultFile

        Remove-Item `
            -Path $CompareFile `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

}

function WBase-HostDeviceInit
{
    # Base on QAT driver installed
    $LocationInfo.FriendlyName = $null
    $LocationInfo.PF.PCI = [System.Array] @()
    $LocationInfo.PF.Number = 0
    $LocationInfo.QatType = $null
    $LocationInfo.IcpQatName = $null
    $LocationInfo.Socket = 0
    $LocationInfo.Socket2PF = 0
    $LocationInfo.PF2VF = 0

    $SocketArray = Get-CimInstance -ClassName win32_processor
    $SocketArrayType = $SocketArray.gettype()
    if ($SocketArrayType.Name -eq "CimInstance") {
        $SocketNumber = 1
    } elseif ($SocketArrayType.Name -eq "Object[]") {
        $SocketNumber = [int]($SocketArray.length)
    } else {
        Win-DebugTimestamp -output ("Host: Can not get the socket number of CPU")
        return $false
    }

    $LocationInfo.Socket = $SocketNumber
    Win-DebugTimestamp -output ("Host: Get the socket number of CPU > {0}" -f $SocketNumber)

    ForEach ($FriendlyName in $FriendlyNames) {
        $devCount = 0
        $PnpDeviceError = $null
        $PnpDeviceObjects = Get-PnpDevice -friendlyname $FriendlyName `
                                          -Status OK `
                                          -ErrorAction SilentlyContinue `
                                          -ErrorVariable PnpDeviceError

        if ([String]::IsNullOrEmpty($PnpDeviceError)) {
            $LocationInfo.FriendlyName = $FriendlyName
            ForEach ($PnpDeviceObject in $PnpDeviceObjects) {
                $LocationPath = Get-PnpDeviceProperty -InstanceId $PnpDeviceObject.DeviceID `
                                                      -KeyName DEVPKEY_Device_LocationPaths
                $LocationPath = $LocationPath.data.split()[0]
                $LocationInfo.PF.PCI += [hashtable] @{
                    Id = $devCount
                    Instance = $LocationPath
                }

                Win-DebugTimestamp -output ("Host: Qat device {0} > {1}" -f $devCount, $LocationPath)
                $devCount++
            }

            Win-DebugTimestamp -output ("Host: There are {0} qat devices" -f $devCount)
            $LocationInfo.PF.Number = $devCount
        }
    }

    if ($LocationInfo.FriendlyName -eq "Intel(R) C62x Accelerator*") {
        $LocationInfo.QatType = "QAT17"
        $LocationInfo.IcpQatName = "icp_qat"
        $LocationInfo.Socket2PF = 3
        $LocationInfo.PF2VF = 16
        $PFNumber = $LocationInfo.Socket2PF
    } elseif ($LocationInfo.FriendlyName -eq "Intel(R) C4xxx Accelerator*") {
        $LocationInfo.QatType = "QAT18"
        $LocationInfo.IcpQatName = "icp_qat"
        $LocationInfo.Socket2PF = 1
        $LocationInfo.PF2VF = 64
        $PFNumber = $SocketNumber * $LocationInfo.Socket2PF
    } elseif ($LocationInfo.FriendlyName -eq "Intel(R) 4xxx Accelerator*") {
        $LocationInfo.QatType = "QAT20"
        $LocationInfo.IcpQatName = "icp_qat4"
        $LocationInfo.Socket2PF = 4
        $LocationInfo.PF2VF = 16
        $PFNumber = $SocketNumber * $LocationInfo.Socket2PF
    } elseif ($LocationInfo.FriendlyName -eq "Intel(R) 401xx Accelerator*") {
        $LocationInfo.QatType = "QAT20"
        $LocationInfo.IcpQatName = "icp_qat4"
        $LocationInfo.Socket2PF = 2
        $LocationInfo.PF2VF = 16
        $PFNumber = $SocketNumber * $LocationInfo.Socket2PF
    } elseif ($LocationInfo.FriendlyName -eq "Intel(R) 402xx Accelerator*") {
        $LocationInfo.QatType = "QAT20"
        $LocationInfo.IcpQatName = "icp_qat4"
        $LocationInfo.Socket2PF = 4
        $LocationInfo.PF2VF = 16
        $PFNumber = $SocketNumber * $LocationInfo.Socket2PF
    } else {
        Win-DebugTimestamp -output ("Host: Can not get the friendly name")
        return $false
    }

    if ($LocationInfo.PF.Number -ne $PFNumber) {
        Win-DebugTimestamp -output ("Host: The number of QAT devices is not equal to {0}" -f $PFNumber)
        return $false
    }

    return $true
}

function WBase-PFDriverPathInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$PFDriverFullPath
    )

    $ReturnValue = $null

    $PFDriverPath = Split-Path -Path $PFDriverFullPath
    $PFDriverName = Split-Path -Path $PFDriverFullPath -Leaf

    # Make the test directories clear
    if (Test-Path -Path $STVWinPath) {
        $ExcludeFiles = @("*.txt", "*.exe")
        Remove-Item `
            -Path $STVWinPath `
            -Exclude $ExcludeFiles `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    } else {
        New-Item -Path $STVWinPath -ItemType Directory | out-null
    }

    if (-not (Test-Path -Path $LocalPFDriverPath)) {
        New-Item -Path $LocalPFDriverPath -ItemType Directory | out-null
    }

    if ([String]::IsNullOrEmpty($LocationInfo.IsWin)) {
        $LocationInfo.IsWin = $true
    }

    if ($LocationInfo.IsWin) {
        $PFIncludeFiles = @("*.pdb", "*.cer", "*.zip")
    } else {
        $PFIncludeFiles = "*.gz"
    }

    $PFCopyPath = "{0}\\*" -f $PFDriverPath
    Copy-Item `
        -Path $PFCopyPath `
        -Destination $LocalPFDriverPath `
        -Include $PFIncludeFiles `
        -Recurse `
        -Force `
        -Confirm:$false `
        -ErrorAction Stop | out-null

    $LocalPFDriverFullPath = "{0}\\{1}" -f $LocalPFDriverPath,  $PFDriverName
    if ($LocationInfo.IsWin) {
        Expand-Archive `
            -Path $LocalPFDriverFullPath `
            -DestinationPath $LocalPFDriverPath `
            -Force `
            -ErrorAction Stop | out-null

        $PFDriverExe = "{0}\\{1}" -f $LocalPFDriverPath, $VMDriverInstallPath.QatSetupPath
        if (Test-Path -Path $PFDriverExe) {
            $ReturnValue = $PFDriverExe
        }
    }

    return $ReturnValue
}

function WBase-STVWinPathInit
{
    Win-DebugTimestamp -output ("Host: STV base path init....")

    # Init file or directory for PF
    $PFDriverFullPath = "{0}\\{1}" -f
        $LocationInfo.PF.DriverPath,
        $LocationInfo.PF.DriverName
    $LocationInfo.PF.DriverExe = WBase-PFDriverPathInit -PFDriverFullPath $PFDriverFullPath

    # Init file or directory for VF
    if ($LocationInfo.HVMode) {
        if (-not (Test-Path -Path $LocalVFDriverPath)) {
            New-Item -Path $LocalVFDriverPath -ItemType Directory | out-null
        }

        if ($LocationInfo.VM.IsWin) {
            $VFIncludeFiles = @("*.pdb", "*.cer", "*.zip")
        } else {
            $VFIncludeFiles = "*.gz"
        }

        $VFCopyPath = "{0}\\*" -f $LocationInfo.VF.DriverPath
        Copy-Item `
            -Path $VFCopyPath `
            -Destination $LocalVFDriverPath `
            -Include $VFIncludeFiles `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null

        # Init file or directory for Linux
        if (-not $LocationInfo.VM.IsWin) {
            if (-not (Test-Path -Path $LocalLinuxPath)) {
                New-Item -Path $LocalLinuxPath -ItemType Directory | out-null
            }
        }
    }

    # Install PF cert on host: qat_cert.cer
    if ($LocationInfo.IsWin) {
        if (Test-Path -Path $Certificate.HostPF) {
            UT-DelCertificate -CertFile $Certificate.HostPF -Remote $false | out-null
            UT-SetCertificate -CertFile $Certificate.HostPF -Remote $false | out-null
        }
    }

    # Create test files
    Foreach ($Type in $TestFileNameArray.Type) {
        Foreach ($Size in $TestFileNameArray.Size) {
            $TestFileFullPath = "{0}\\{1}{2}.txt" -f $STVWinPath, $Type, $Size
            if (-not (Test-Path -Path $TestFileFullPath)) {
                WBase-CreateTestFile `
                    -Remote $false `
                    -TestFileType $Type `
                    -TestFileSize $Size | out-null
            }
        }
    }

    # Copy all exe files for tracelog
    if (-not (Test-Path -Path $TraceLogOpts.ExePath)) {
        Copy-Item `
            -Path ("{0}\\utils\\tracelog.exe" -f $QATTESTPATH) `
            -Destination $TraceLogOpts.ExePath `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    if (-not (Test-Path -Path $TraceLogOpts.PDBExePath)) {
        Copy-Item `
            -Path ("{0}\\utils\\tracepdb.exe" -f $QATTESTPATH) `
            -Destination $TraceLogOpts.PDBExePath `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    if (-not (Test-Path -Path $TraceLogOpts.FMTExePath)) {
        Copy-Item `
            -Path ("{0}\\utils\\tracefmt.exe" -f $QATTESTPATH) `
            -Destination $TraceLogOpts.FMTExePath `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    # Init test path for process
    if (Test-Path -Path $LocalProcessPath) {
        Remove-Item `
            -Path $LocalProcessPath `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }
    New-Item -Path $LocalProcessPath -ItemType Directory | out-null

    # Make the automation directories if they do not exist
    if (-not (Test-Path -Path $VHDAndTestFiles.ParentsVMPath)) {
        Win-DebugTimestamp -output (
            "Create new path: {0}" -f $VHDAndTestFiles.ParentsVMPath
        )
        New-Item -Path $VHDAndTestFiles.ParentsVMPath -ItemType Directory | out-null
    }

    if (-not (Test-Path -Path $VHDAndTestFiles.ChildVMPath)) {
        Win-DebugTimestamp -output (
            "Create new path: {0}" -f $VHDAndTestFiles.ChildVMPath
        )
        New-Item -Path $VHDAndTestFiles.ChildVMPath -ItemType Directory | out-null
    }

    Win-DebugTimestamp -output ("Host: STV base path init: Completed")
}

function WBase-LocationInfoInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$BertaResultPath,

        [Parameter(Mandatory=$True)]
        [hashtable]$QatDriverFullPath,

        [Parameter(Mandatory=$True)]
        [hashtable]$BertaConfig
    )

    # Init location Info
    if ([String]::IsNullOrEmpty($LocationInfo.HVMode)) {
        $LocationInfo.HVMode = $BertaConfig.HV_mode
    }

    $LocationInfo.UQMode = $BertaConfig.UQ_mode
    $LocationInfo.TestMode = $BertaConfig.test_mode
    $LocationInfo.DebugMode = $BertaConfig.DebugMode
    $LocationInfo.VerifierMode = $BertaConfig.driver_verifier
    $LocationInfo.BertaResultPath = $BertaResultPath
    $LocationInfo.PF.DriverPath = Split-Path -Path $QatDriverFullPath.PF
    $LocationInfo.PF.DriverName = Split-Path -Path $QatDriverFullPath.PF -Leaf
    if ($LocationInfo.HVMode) {
        $LocationInfo.VF.DriverPath = Split-Path -Path $QatDriverFullPath.VF
        $LocationInfo.VF.DriverName = Split-Path -Path $QatDriverFullPath.VF -Leaf
        $LocationInfo.PDBNameArray.Host = [System.Array] @("IcpQat")
        $LocationInfo.PDBNameArray.Remote = [System.Array] @("IcpQat", "CfQat", "UCpmProv", "CpmBCrypt")
    } else {
        $LocationInfo.PDBNameArray.Host = [System.Array] @("IcpQat", "CfQat", "UCpmProv", "CpmBCrypt")
        $LocationInfo.PDBNameArray.Remote = [System.Array] @()
    }

    if ($LocationInfo.IsWin) {
        $LocationInfo.PF.DriverExe = "{0}\\{1}" -f
            $LocationInfo.PF.DriverPath,
            $VMDriverInstallPath.QatSetupPath
    }

    $LocationInfo.Domain.ExecutingServer = $env:COMPUTERNAME
    if ([String]::IsNullOrEmpty($BertaConfig.TargetServer)) {
        $LocationInfo.Domain.TargetServer = $null
    } else {
        $LocationInfo.Domain.TargetServer = $BertaConfig.TargetServer
    }

    # Init test path on host
    WBase-STVWinPathInit | out-null

    # Remove child vm's
    if (-not $LocationInfo.HVMode) {
        $VMList = Get-VM
        if (-not [String]::IsNullOrEmpty($VMList)) {
            Foreach ($VM in $VMList) {
                HV-RemoveVM -VMName $VM.Name | out-null
            }
        }
    }

    # Double check win QAT driver on host
    $InstallFlag = $false
    $UninstallFlag = $false

    $CheckDriverResult = WBase-CheckDriverInstalled -Remote $false
    if ($CheckDriverResult) {
        $DoubleCheckDriverResult = WBase-DoubleCheckDriver -Remote $false
        if ($DoubleCheckDriverResult) {
            $HVModeFlag = WBase-CheckDriverHVMode -CheckFlag $LocationInfo.HVMode
            if ($HVModeFlag) {
                Win-DebugTimestamp -output ("Host: Qat driver installed is correct")
            } else {
                $InstallFlag = $true
                $UninstallFlag = $true
            }
        } else {
            $InstallFlag = $true
            $UninstallFlag = $true
        }
    } else {
        $InstallFlag = $true
    }

    if ($UninstallFlag) {
        Win-DebugTimestamp -output ("Host: Uninstall Qat driver > {0}" -f $LocationInfo.PF.DriverExe)
        WBase-InstallAndUninstallQatDriver -SetupExePath $LocationInfo.PF.DriverExe `
                                           -Operation $false `
                                           -Remote $false
        $CheckunInstallDriverResult = WBase-CheckDriverInstalled -Remote $false
        if ($CheckunInstallDriverResult) {
            throw ("Can not uninstall Qat driver on local host")
        }
    }

    if ($InstallFlag) {
        Win-DebugTimestamp -output ("Host: Install Qat driver > {0}" -f $LocationInfo.PF.DriverExe)
        WBase-InstallAndUninstallQatDriver -SetupExePath $LocationInfo.PF.DriverExe `
                                           -Operation $true `
                                           -Remote $false `
                                           -UQMode $LocationInfo.UQMode
        $CheckInstallDriverResult = WBase-CheckDriverInstalled -Remote $false
        if (-not $CheckInstallDriverResult) {
            throw ("Can not install Qat driver on local host")
        }
    }

    # Init QAT devices info
    $HostDeviceInitFlag = WBase-HostDeviceInit
    if (-not $HostDeviceInitFlag) {
        throw ("Init the QAT devices is failed, please double check by manual")
    }

    # Check UQ mode
    $DisableDeviceFlag = $false
    $UQModeStatus = UT-CheckUQMode `
        -CheckFlag $LocationInfo.UQMode `
        -Remote $false
    if (-not $UQModeStatus) {
        $DisableDeviceFlag = $true
        UT-SetUQMode `
            -UQMode $LocationInfo.UQMode `
            -Remote $false | out-null
    }

    UT-WorkAround `
        -Remote $false `
        -DisableFlag $DisableDeviceFlag | out-null

    # Correct ICPQAT file name
    $TraceLogOpts.PDBDriverPath.Host.IcpQat = "{0}\\{1}.pdb" -f
        $LocalPFDriverPath,
        $LocationInfo.IcpQatName
    $TraceLogOpts.PDBDriverPath.Remote.IcpQat = "{0}\\{1}.pdb" -f
        $LocalVFDriverPath,
        $LocationInfo.IcpQatName
    $TraceLogOpts.PDBFullPath.IcpQat = "{0}\\TraceLog\\PDB\\{1}.pdb" -f
        $STVWinPath,
        $LocationInfo.IcpQatName

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

    $PDBIncludeFiles = @("*.pdb")
    $PDBCopyPath = "{0}\\*" -f $LocalPFDriverPath
    Copy-Item `
        -Path $PDBCopyPath `
        -Destination $TraceLogOpts.PDBPath `
        -Include $PDBIncludeFiles `
        -Recurse `
        -Force `
        -Confirm:$false `
        -ErrorAction Stop | out-null

    # Start trace log tool
    UT-TraceLogStart -Remote $false | out-null

    Win-DebugTimestamp -output ("Local info:")
    Win-DebugTimestamp -output ("              HVMode : {0}" -f $LocationInfo.HVMode)
    Win-DebugTimestamp -output ("              UQMode : {0}" -f $LocationInfo.UQMode)
    Win-DebugTimestamp -output ("            TestMode : {0}" -f $LocationInfo.TestMode)
    Win-DebugTimestamp -output ("           DebugMode : {0}" -f $LocationInfo.DebugMode)
    Win-DebugTimestamp -output ("        VerifierMode : {0}" -f $LocationInfo.VerifierMode)
    Win-DebugTimestamp -output ("             QatType : {0}" -f $LocationInfo.QatType)
    Win-DebugTimestamp -output ("        FriendlyName : {0}" -f $LocationInfo.FriendlyName)
    Win-DebugTimestamp -output ("              Socket : {0}" -f $LocationInfo.Socket)
    Win-DebugTimestamp -output ("           Socket2PF : {0}" -f $LocationInfo.Socket2PF)
    Win-DebugTimestamp -output ("               PF2VF : {0}" -f $LocationInfo.PF2VF)
    Win-DebugTimestamp -output ("            PFNumber : {0}" -f $LocationInfo.PF.Number)
    Win-DebugTimestamp -output ("                 PFs : {0}" -f $LocationInfo.PF.PCI)
    Win-DebugTimestamp -output ("     BertaResultPath : {0}" -f $LocationInfo.BertaResultPath)
    Win-DebugTimestamp -output ("     PFQatDriverPath : {0}" -f $LocationInfo.PF.DriverPath)
    Win-DebugTimestamp -output ("     PFQatDriverName : {0}" -f $LocationInfo.PF.DriverName)
    Win-DebugTimestamp -output ("      PFQatDriverExe : {0}" -f $LocationInfo.PF.DriverExe)
    Win-DebugTimestamp -output ("     VFQatDriverPath : {0}" -f $LocationInfo.VF.DriverPath)
    Win-DebugTimestamp -output ("     VFQatDriverName : {0}" -f $LocationInfo.VF.DriverName)
    Win-DebugTimestamp -output ("          IcpQatName : {0}" -f $LocationInfo.IcpQatName)
    Win-DebugTimestamp -output ("     ExecutingServer : {0}" -f $LocationInfo.Domain.ExecutingServer)
    Win-DebugTimestamp -output ("        TargetServer : {0}" -f $LocationInfo.Domain.TargetServer)
}

function WBase-GetDriverPath
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$BuildPath
    )

    $ReturnValue =  [hashtable] @{
        PV = $null
        VF = $null
    }

    $BuildFile = "{0}\\pfvf_build.txt" -f $BuildPath
    if (Test-Path -Path $BuildFile) {
        $PfvfBuildContents = Get-Content -Path $BuildFile
        $PFRelativePath = ($PfvfBuildContents | Where-Object {$_.StartsWith("PF")}).Split()[1]
        $VFRelativePath = ($PfvfBuildContents | Where-Object {$_.StartsWith("VF")}).Split()[1]

        if ([String]::IsNullOrEmpty($PFRelativePath)) {
            throw ("Can not get PF driver on driver config > {0}" -f $BuildFile)
        } else {
            $PFName = Split-Path -Path $PFRelativePath -Leaf
            $PFPath = Split-Path -Path $PFRelativePath
            if ([String]::IsNullOrEmpty($PFPath)) {
                $PFPath = $BuildPath
            } else {
                $PFPath = "{0}\\{1}" -f $BuildPath, $PFPath
            }

            $PFFullPathArray = WBase-FindFiles `
                -Path $PFPath `
                -Key ("{0}.*" -f $PFName) `
                -Remote $false
            if ([String]::IsNullOrEmpty($PFFullPathArray)) {
                throw ("Can not get PF driver > {0}\\{1}" -f $PFPath, $PFName)
            } else {
                if ([string]($PFFullPathArray.gettype()) -eq "string") {
                    $ReturnValue.PF = $PFFullPathArray
                } else {
                    if ([String]::IsNullOrEmpty($LocationInfo.IsWin)) {
                        # Default on Windows
                        $ReturnValue.PF = "{0}\\{1}.zip" -f $BuildPath, $PFRelativePath
                    } else {
                        if ($LocationInfo.IsWin) {
                            $ReturnValue.PF = "{0}\\{1}.zip" -f $BuildPath, $PFRelativePath
                        } else {
                            $ReturnValue.PF = "{0}\\{1}.tar.gz" -f $BuildPath, $PFRelativePath
                        }
                    }
                }
            }
        }

        if (-not ([String]::IsNullOrEmpty($VFRelativePath))) {
            $VFName = Split-Path -Path $VFRelativePath -Leaf
            $VFPath = Split-Path -Path $VFRelativePath
            if ([String]::IsNullOrEmpty($VFPath)) {
                $VFPath = $BuildPath
            } else {
                $VFPath = "{0}\\{1}" -f $BuildPath, $VFPath
            }

            $VFFullPathArray = WBase-FindFiles `
                -Path $VFPath `
                -Key ("{0}.*" -f $VFName) `
                -Remote $false
            if ([String]::IsNullOrEmpty($VFFullPathArray)) {
                throw ("Can not get VF driver > {0}\\{1}" -f $VFPath, $VFName)
            } else {
                if ([string]($VFFullPathArray.gettype()) -eq "string") {
                    $ReturnValue.VF = $VFFullPathArray
                } else {
                    if ([String]::IsNullOrEmpty($LocationInfo.VM.IsWin)) {
                        throw ("Can not choose VF driver: {0}" -f $VFFullPathArray)
                    } else {
                        if ($LocationInfo.VM.IsWin) {
                            $ReturnValue.VF = "{0}\\{1}.zip" -f $BuildPath, $VFRelativePath
                        } else {
                            $ReturnValue.VF = "{0}\\{1}.tar.gz" -f $BuildPath, $VFRelativePath
                        }
                    }
                }
            }
        }
    } else {
        throw ("Can not get build file > {0}" -f $BuildFile)
    }

    Win-DebugTimestamp -output ("PF driver: {0}" -f $ReturnValue.PF)
    Win-DebugTimestamp -output ("VF driver: {0}" -f $ReturnValue.VF)

    return $ReturnValue
}

function WBase-FindFiles
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [Parameter(Mandatory=$True)]
        [string]$Path,

        [Parameter(Mandatory=$True)]
        [string]$Key,

        [object]$Session
    )

    # Need to check return value is null
    $ReturnValue = @()

    if ($Remote) {
        $FindFileArray = Invoke-Command -Session $Session -ScriptBlock {
            Param($Path, $Key)
            $ReturnValue = Get-ChildItem -Path $Path -Recurse -Name $Key
            return $ReturnValue
        } -ArgumentList $Path, $Key
    } else {
        $FindFileArray = Get-ChildItem -Path $Path -Recurse -Name $Key
    }

    if (-not ([String]::IsNullOrEmpty($FindFileArray))) {
        Foreach ($FindFile in $FindFileArray) {
            $ReturnValue += "{0}\\{1}" -f $Path, $FindFile
        }
    }

    return $ReturnValue
}

function WBase-ClearDir
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [Parameter(Mandatory=$True)]
        [string]$Path,

        [object]$Session
    )

    if ($Remote) {
        Invoke-Command -Session $Session -ScriptBlock {
            Param($Path)
            if (Test-Path -Path $Path) {
                Get-Item -Path $Path | Remove-Item -Recurse -Force | out-null
            }

            New-Item -Path $Path -ItemType Directory | out-null
        } -ArgumentList $Path | out-null
    } else {
        Invoke-Command -ScriptBlock {
            Param($Path)
            if (Test-Path -Path $Path) {
                Get-Item -Path $Path | Remove-Item -Recurse -Force | out-null
            }

            New-Item -Path $Path -ItemType Directory | out-null
        } -ArgumentList $Path | out-null
    }
}

function WBase-CopyDir
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [Parameter(Mandatory=$True)]
        [string]$Path,

        [Parameter(Mandatory=$True)]
        [string]$Destination,

        [object]$Session
    )

    $CopyPath = "{0}\\*" -f $Path
    if ($Remote) {
        WBase-ClearDir `
            -Remote $Remote `
            -Path $Destination `
            -Session $Session | out-null

        Copy-Item `
            -ToSession $Session `
            -Path $CopyPath `
            -Destination $Destination `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    } else {
        WBase-ClearDir `
            -Remote $Remote `
            -Path $Destination | out-null

        Copy-Item `
            -Path $CopyPath `
            -Destination $Destination `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }
}

# About HV mode
function WBase-CheckDriverHVMode
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$CheckFlag = $false
    )

    $ReturnValue = $false

    $HVModeFlag = $false
    $InstalledLogFile = "C:\Program Files\Intel\Intel(R) QuickAssist Technology\QATInstallSummary.log"
    if (Test-Path -Path $InstalledLogFile) {
        $InstalledLog = Get-Content -Path $InstalledLogFile
        Foreach ($line in $InstalledLog) {
            if ($line -match "Virtualization host install") {
                $HVModeFlag = $true
            }
        }
    } else {
        Win-DebugTimestamp -output ("Host: The file is not exist > " -f $InstalledLogFile)
    }

    if ($HVModeFlag -eq $CheckFlag) {
        $ReturnValue = $true
    } else {
        $ReturnValue = $false
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "Host: Double check QAT driver with HVMode > passed"
        )
    } else {
        Win-DebugTimestamp -output (
            "Host: Double check QAT driver with HVMode > failed"
        )
    }

    return $ReturnValue
}

# About test
function WBase-CreateTestFile
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    $TestSourceFile = "{0}\\{1}{2}.txt" -f
        $STVWinPath,
        $TestFileType,
        $TestFileSize
    $TestFileSizeBytes = $TestFileSize * 1024 * 1024

    if ($TestFileType -eq "high") {
        Win-DebugTimestamp -output (
            "{0}: Create {1}M source file for high compress ratio sample > {2}" -f
                $LogKeyWord,
                $TestFileSize,
                $TestSourceFile
        )
        if ($Remote) {
            Invoke-Command -Session $Session -ScriptBlock {
                Param($TestSourceFile, $TestFileSizeBytes)
                fsutil file createnew $TestSourceFile $TestFileSizeBytes
            } -ArgumentList $TestSourceFile, $TestFileSizeBytes | out-null
        } else {
            Invoke-Command -ScriptBlock {
                Param($TestSourceFile, $TestFileSizeBytes)
                fsutil file createnew $TestSourceFile $TestFileSizeBytes
            } -ArgumentList $TestSourceFile, $TestFileSizeBytes | out-null
        }
    } elseif ($TestFileType -eq "calgary") {
        Win-DebugTimestamp -output (
            "{0}: Create {1}M source file for calgary standard sample > {2}" -f
                $LogKeyWord,
                $TestFileSize,
                $TestSourceFile
        )
        $calgarySourceFile = "{0}\\calgary.txt" -f
            $VHDAndTestFiles.SourceTestPath
        $calgaryTestFile = "{0}\\calgary{1}.txt" -f
            $VHDAndTestFiles.SourceTestPath,
            $TestFileSize
        if (-not (Test-Path -Path $calgarySourceFile)) {
            $calgarySourceFile = "{0}\\utils\\calgary.txt" -f $QATTESTPATH
        }

        if (-not (Test-Path -Path $calgaryTestFile)) {
            $calgaryContent = Get-Content -Path $calgarySourceFile
            $calgaryFileSize = [int]((Get-ChildItem $calgarySourceFile -recurse |
                Measure-Object -property length -sum).sum)
            for ($i = 0; $i -le [int]($TestFileSizeBytes / $calgaryFileSize); $i++) {
                $calgaryContent | Out-File $calgaryTestFile -Append -Encoding ascii
            }
        }

        if ($Remote) {
            Copy-Item `
                -ToSession $Session `
                -Path $calgaryTestFile `
                -Destination $TestSourceFile
        } else {
            Copy-Item -Path $calgaryTestFile -Destination $TestSourceFile
        }
    } elseif ($TestFileType -eq "random") {
        Win-DebugTimestamp -output (
            "{0}: Create {1}M test file for total randomly sample > {2}" -f
                $LogKeyWord,
                $TestFileSize,
                $TestSourceFile
        )
        $randomTestFile = "{0}\\random{1}.txt" -f
            $VHDAndTestFiles.SourceTestPath,
            $TestFileSize
        if (!(Test-Path -Path $randomTestFile)) {
            $randomContent = -join(1..(1024 * 1024) |
                %{[char][int]((48..57 + 65..90 + 97..122) | Get-Random)})
            for ($i = 0; $i -le [int]($TestFileSizeBytes / 1024 / 1024); $i++) {
                $randomContent | Out-File $randomTestFile -Append -Encoding ascii
            }
        }

        if ($Remote) {
            Copy-Item `
                -ToSession $Session `
                -Path $randomTestFile `
                -Destination $TestSourceFile
        } else {
            Copy-Item -Path $randomTestFile -Destination $TestSourceFile
        }
    } else {
        Win-DebugTimestamp -output (
            "{0}: The test does not support input file type > {1}" -f
                $LogKeyWord,
                $TestFileType
        )
    }
}

function WBase-AnalyzeTestCaseName
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$TestCaseName
    )

    $ReturnValue = [hashtable] @{
        Parcomp = [hashtable] @{
            Provider = @("qat")
            Chunk = @(64)
            Block = @(4096)
            CompressType = @("Compress")
            Level = @(1)
            CompressionType = @("dynamic")
            Iteration = @(100)
            Thread = @(8)
            TestFileType = @("high")
            TestFileSize = @(200)
        }
        CNGTest = [hashtable] @{
            Provider = @("qa")
            Algo = @("rsa")
            Operation = @("encrypt")
            KeyLength = @(4096)
            Padding = @("pkcs1")
            Ecccurve = @("nistP256")
            Iteration = @(10000)
            Thread = @(1)
        }
        VMVFOS = $null
        Operation = @("heartbeat")
    }

    $AnalyzeTestHVMode = $null
    $AnalyzeTestHostIsWin = $null
    $AnalyzeTestVMIsWin = $null
    $AnalyzeTestUQMode = $null
    $AnalyzeTestVMNumer = $null
    $AnalyzeTestVFNumer = $null
    $AnalyzeTestVMOS = $null
    $AnalyzeTestQatType = $null
    $TestNameFieldArray = $TestCaseName.split("_")
    Foreach ($TestNameField in $TestNameFieldArray) {
        # For All
        if ($TestNameField -eq "Host") {
            $AnalyzeTestHVMode = $false
            $AnalyzeTestHostIsWin = $true
            $AnalyzeTestVMIsWin = $null
            continue
        }

        if ($TestNameField -eq "WTW") {
            $AnalyzeTestHVMode = $true
            $AnalyzeTestHostIsWin = $true
            $AnalyzeTestVMIsWin = $true
            continue
        }

        if ($TestNameField -eq "WTL") {
            $AnalyzeTestHVMode = $true
            $AnalyzeTestHostIsWin = $true
            $AnalyzeTestVMIsWin = $false
            $BertaConfig["UQ_mode"] = $false
            continue
        }

        if ($TestNameField -eq "NUQ") {
            $AnalyzeTestUQMode = $false
            continue
        }

        if ($TestNameField -eq "UQ") {
            $AnalyzeTestUQMode = $true
            continue
        }

        if ($TestNameField -match "vm") {
            $AnalyzeTestVMNumer = $TestNameField
            continue
        }

        if ($TestNameField -match "vf") {
            $AnalyzeTestVFNumer = $TestNameField
            continue
        }

        if (($TestNameField -match "windows") -or
            ($TestNameField -match "ubuntu")) {
            $AnalyzeTestVMOS = $TestNameField
            continue
        }

        if (($TestNameField -match "QAT1") -or
            ($TestNameField -match "QAT2")) {
            $AnalyzeTestQatType = $TestNameField
            continue
        }

        if ($TestNameField -in $AllTestType.Operation) {
            $ReturnValue.Operation = ($TestNameField)
            continue
        }

        if ($TestNameField -match "Iteration") {
            $ReturnValue.Parcomp.Iteration = ([int]$TestNameField.Substring(9))
            $ReturnValue.CNGTest.Iteration = ([int]$TestNameField.Substring(9))
            continue
        }

        if ($TestNameField -match "Thread") {
            $ReturnValue.Parcomp.Thread = ([int]$TestNameField.Substring(6))
            $ReturnValue.CNGTest.Thread = ([int]$TestNameField.Substring(6))
            continue
        }

        # For CNGTest
        if ($TestNameField -in $CNGTestProvider) {
            $ReturnValue.CNGTest.Provider = ($TestNameField)
            continue
        }

        if ($TestNameField -in $CNGTestAlgo) {
            $ReturnValue.CNGTest.Algo = ($TestNameField)
            continue
        }

        if ($TestNameField -in $CNGTestEcccurve) {
            $ReturnValue.CNGTest.Ecccurve = ($TestNameField)
            continue
        }

        if ($TestNameField -in $CNGTestPadding) {
            $ReturnValue.CNGTest.Padding = ($TestNameField)
            continue
        }

        if ($TestNameField -in $CNGTestOperation) {
            $ReturnValue.CNGTest.Operation = ($TestNameField)
            continue
        }

        if ($TestNameField -match "KeyLength") {
            $ReturnValue.CNGTest.KeyLength = ([int]$TestNameField.Substring(9))
            continue
        }

        # For Parcomp
        if ($TestNameField -in $ParcompProvider) {
            $ReturnValue.Parcomp.Provider = ($TestNameField)
            continue
        }

        if ($TestNameField -in $ParcompCompressType) {
            $ReturnValue.Parcomp.CompressType = ($TestNameField)
            continue
        }

        if ($TestNameField -in $ParcompCompressionType) {
            $ReturnValue.Parcomp.CompressionType = ($TestNameField)
            continue
        }

        if ($TestNameField -match "Chunk") {
            $ReturnValue.Parcomp.Chunk = ([int]$TestNameField.Substring(5))
            continue
        }

        if ($TestNameField -match "Block") {
            $ReturnValue.Parcomp.Block = ([int]$TestNameField.Substring(5))
            continue
        }

        if ($TestNameField -match "Level") {
            $ReturnValue.Parcomp.Level = ([int]$TestNameField.Substring(5))
            continue
        }

        if (($TestNameField -match "high") -or
            ($TestNameField -match "random") -or
            ($TestNameField -match "calgary")) {
            $ReturnValue.Parcomp.TestFileType = ($TestNameField.Substring(0, ($TestNameField.length - 3)))
            $ReturnValue.Parcomp.TestFileSize = ([int]$TestNameField.Substring(($TestNameField.length - 3)))
            continue
        }
    }

    if ([String]::IsNullOrEmpty($AnalyzeTestHVMode)) {
        throw ("The flag of HVMode is null")
    } else {
        if ($AnalyzeTestHVMode -ne $LocationInfo.HVMode) {
            throw ("The flag of HVMode is not match")
        }
    }

    if ([String]::IsNullOrEmpty($AnalyzeTestHostIsWin)) {
        throw ("The flag of host OS is null")
    } else {
        if ($AnalyzeTestHostIsWin -ne $LocationInfo.IsWin) {
            throw ("The flag of host OS is not match")
        }
    }

    if ([String]::IsNullOrEmpty($AnalyzeTestUQMode)) {
        throw ("The flag of UQMode is null")
    } else {
        if ($AnalyzeTestUQMode -ne $LocationInfo.UQMode) {
            throw ("The flag of UQMode is not match")
        }
    }

    if ([String]::IsNullOrEmpty($AnalyzeTestQatType)) {
        throw ("The type of QAT is null")
    } else {
        if ($AnalyzeTestQatType -ne $LocationInfo.QatType) {
            throw ("The type of QAT is not match")
        }
    }

    if ($LocationInfo.HVMode) {
        if ([String]::IsNullOrEmpty($AnalyzeTestVMIsWin)) {
            throw ("The flag of VM OS is null")
        } else {
            if ($AnalyzeTestVMIsWin -ne $LocationInfo.VM.IsWin) {
                throw ("The flag of VM OS is not match")
            }
        }

        if ([String]::IsNullOrEmpty($AnalyzeTestVMNumer)) {
            throw ("The number of VM is null")
        }

        if ([String]::IsNullOrEmpty($AnalyzeTestVFNumer)) {
            throw ("The number of VF is null")
        }

        if ([String]::IsNullOrEmpty($AnalyzeTestVMOS)) {
            throw ("The OS of VM is null")
        }

        $ReturnValue.VMVFOS = "{0}_{1}_{2}" -f
            $AnalyzeTestVMNumer,
            $AnalyzeTestVFNumer,
            $AnalyzeTestVMOS
    }

    if ($LocationInfo.UQMode) {
        $CurrentBuildNumber = [int]((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\").CurrentBuildNumber)
        if ($CurrentBuildNumber -lt 25000) {
            throw ("Not support UQ mode on windows-2022-{0}" -f $CurrentBuildNumber)
        }
    }

    return $ReturnValue
}

# About QAT driver
function WBaseGetDriverInfoFromRegedit
{
    Param(
        [bool]$Remote = $false,

        [object]$Session
    )

    $ReturnValue = [hashtable] @{
        DisplayName = $null
        DisplayVersion = $null
        InstallSource = $null
        LocalPackage = $null
        EnableUQ = 0
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    if ($Remote) {
        $VMReturnValue = Invoke-Command -Session $Session -ScriptBlock {
            $ReturnValue = [hashtable] @{
                DisplayName = $null
                DisplayVersion = $null
                InstallSource = $null
                LocalPackage = $null
                EnableUQ = 0
            }

            $InstallProducts = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\*"
            $InstallProducts | foreach-object {
                $FileNametmp = Split-Path -Path $_ -Leaf
                $regeditKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\{0}\InstallProperties" -f $FileNametmp
                $InstallProperties = Get-ItemProperty $regeditKey
                if ($InstallProperties.DisplayName -match "QuickAssist Technology") {
                    $ReturnValue.DisplayName = $InstallProperties.DisplayName
                    $ReturnValue.DisplayVersion = $InstallProperties.DisplayVersion
                    $ReturnValue.InstallSource = $InstallProperties.InstallSource
                    $ReturnValue.LocalPackage = $InstallProperties.LocalPackage
                }
            }

            $regeditKey = "HKLM:\SYSTEM\CurrentControlSet\Services\icp_qat4\UQ"
            if (Test-Path -Path $regeditKey) {
                $ReturnValue.EnableUQ = (Get-ItemProperty $regeditKey).EnableUQ
            }

            return $ReturnValue
        }

        $ReturnValue.DisplayName = $VMReturnValue.DisplayName
        $ReturnValue.DisplayVersion = $VMReturnValue.DisplayVersion
        $ReturnValue.InstallSource = $VMReturnValue.InstallSource
        $ReturnValue.LocalPackage = $VMReturnValue.LocalPackage
        $ReturnValue.EnableUQ = $VMReturnValue.EnableUQ
    } else {
        $InstallProducts = Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\*"
        $InstallProducts | foreach-object {
            $FileNametmp = Split-Path -Path $_ -Leaf
            $regeditKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\{0}\InstallProperties" -f $FileNametmp
            $InstallProperties = Get-ItemProperty $regeditKey
            if ($InstallProperties.DisplayName -match "QuickAssist Technology") {
                $ReturnValue.DisplayName = $InstallProperties.DisplayName
                $ReturnValue.DisplayVersion = $InstallProperties.DisplayVersion
                $ReturnValue.InstallSource = $InstallProperties.InstallSource
                $ReturnValue.LocalPackage = $InstallProperties.LocalPackage
            }
        }

        $regeditKey = "HKLM:\SYSTEM\CurrentControlSet\Services\icp_qat4\UQ"
        if (Test-Path -Path $regeditKey) {
            $ReturnValue.EnableUQ = (Get-ItemProperty $regeditKey).EnableUQ
        }
    }

    <#
    Win-DebugTimestamp -output ("{0}: Get QAT driver information from regedit:" -f $LogKeyWord)
    Win-DebugTimestamp -output ("{0}:        DisplayName : {1}" -f $LogKeyWord, $ReturnValue.DisplayName)
    Win-DebugTimestamp -output ("{0}:     DisplayVersion : {1}" -f $LogKeyWord, $ReturnValue.DisplayVersion)
    Win-DebugTimestamp -output ("{0}:      InstallSource : {1}" -f $LogKeyWord, $ReturnValue.InstallSource)
    Win-DebugTimestamp -output ("{0}:       LocalPackage : {1}" -f $LogKeyWord, $ReturnValue.LocalPackage)
    Win-DebugTimestamp -output ("{0}:           EnableUQ : {1}" -f $LogKeyWord, $ReturnValue.EnableUQ)
    #>

    return $ReturnValue
}

function WBaseHandleUninstallingResidues
{
    $CheckPaths = [System.Array] @(
        "C:\\Windows\\System32\\drivers",
        "C:\\Windows\\System32\\DriverStore\\FileRepository"
    )

    $URFiles = [System.Array] @()
    Foreach ($CheckPath in $CheckPaths) {
        if (Test-Path -Path $CheckPath) {
            $CheckFiles = Get-ChildItem `
                -Path $CheckPath `
                -Filter "icp_qat*" `
                -Recurse `
                -ErrorAction SilentlyContinue `
                -Force

            $CheckFiles | ForEach-Object {
                if (Test-Path -Path $_ -PathType Leaf) {
                    $URFiles += $_
                }
            }
        }
    }

    Foreach ($URFile in $URFiles) {
        Invoke-Command -ScriptBlock {
            Param($URFile)

            $localPath = (pwd).path
            $URPath = $URFile.DirectoryName
            $URName = $URFile.Name
            cd $URPath
            takeown /f $URName
            cacls $URName /P Administrator:F /E

            $RemoveError = $null
            Remove-Item `
                -Path $URFile `
                -ErrorAction SilentlyContinue `
                -ErrorVariable RemoveError
            if (-not [String]::IsNullOrEmpty($RemoveError)) {
                $RenameError = $null
                Rename-Item `
                    -Path $URFile `
                    -NewName ("{0}.txt" -f $URFile) `
                    -ErrorAction SilentlyContinue `
                    -ErrorVariable RenameError
                if ([String]::IsNullOrEmpty($RenameError)) {
                    $RemoveError = $null
                    Remove-Item `
                        -Path ("{0}.txt" -f $URFile) `
                        -ErrorAction SilentlyContinue `
                        -ErrorVariable RemoveError
                }
            }

            cd $localPath
        } -ArgumentList $URFile | out-null

        if (-not (Test-Path -Path $URFile)) {
            Win-DebugTimestamp -output ("Host: Delete uninstalling residues file > {0}" -f $URFile)
        }
    }
}

function WBase-InstallAndUninstallQatDriver
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$SetupExePath,

        [Parameter(Mandatory=$True)]
        [bool]$Operation,

        [bool]$Remote = $true,

        [bool]$UQMode = $false,

        [object]$Session,

        [bool]$Wait = $true
    )

    # Handle uninstalling residues on Host: before
    if ($Operation) {
        # Install
        if (!$Remote) {
            # Remove all qat devices
            ForEach ($FriendlyName in $FriendlyNames) {
                $PnpDeviceError = $null
                $PnpDeviceObjects = Get-PnpDevice -friendlyname $FriendlyName `
                                                  -ErrorAction SilentlyContinue `
                                                  -ErrorVariable PnpDeviceError

                if ([String]::IsNullOrEmpty($PnpDeviceError)) {
                    ForEach ($PnpDeviceObject in $PnpDeviceObjects) {
                        &"pnputil" /remove-device -InstanceId $PnpDeviceObject.InstanceId | out-null
                    }
                }
            }

            # Remove uninstalling residues files
            WBaseHandleUninstallingResidues

            # Remove installing path
            if (Test-Path -Path $QatDriverInstallArgs.InstallPath) {
                Get-Item -Path $QatDriverInstallArgs.InstallPath | Remove-Item -Recurse
            }
        }
    } else {
        # Uninstall
        if (!$Remote) {
            # Remove all qat devices
            ForEach ($FriendlyName in $FriendlyNames) {
                $PnpDeviceError = $null
                $PnpDeviceObjects = Get-PnpDevice -friendlyname $FriendlyName `
                                                  -ErrorAction SilentlyContinue `
                                                  -ErrorVariable PnpDeviceError

                if ([String]::IsNullOrEmpty($PnpDeviceError)) {
                    ForEach ($PnpDeviceObject in $PnpDeviceObjects) {
                        &"pnputil" /remove-device -InstanceId $PnpDeviceObject.InstanceId | out-null
                    }
                }
            }

            # Double check the IntelQAT.msi file exist
            $MSIFilePath =  Split-Path -Path $SetupExePath
            $MSIFile = "{0}\IntelQAT.msi" -f $MSIFilePath
            $DriverInfo = WBaseGetDriverInfoFromRegedit
            $DriverLocalPackage = $DriverInfo.LocalPackage
            if (-not [String]::IsNullOrEmpty($DriverLocalPackage)) {
                if (Test-Path -Path $DriverLocalPackage) {
                    Get-Item -Path $DriverLocalPackage | Remove-Item -Recurse
                }
                Copy-Item -Path $MSIFile -Destination $DriverLocalPackage -Force -ErrorAction Stop | out-null
            }
        }
    }

    # Install or uninstall QAT driver on Host or VM
    if ($Operation) {
        if ($Remote) {
            Invoke-Command -Session $Session -ScriptBlock {
                                                            Param($SetupExePath, $QatDriverInstallArgs, $UQMode)
                                                            if ($UQMode) {
                                                                &$SetupExePath $QatDriverInstallArgs.UQInstall.split()
                                                            } else {
                                                                &$SetupExePath $QatDriverInstallArgs.Install.split()
                                                            }
                                                            } -ArgumentList $SetupExePath, $QatDriverInstallArgs, $UQMode | out-null
        } else {
            if ($LocationInfo.HVMode) {
                Invoke-Command -ScriptBlock {
                                              Param($SetupExePath, $QatDriverInstallArgs, $UQMode)
                                              if ($UQMode) {
                                                  &$SetupExePath $QatDriverInstallArgs.UQHyperV.split()
                                              } else {
                                                  &$SetupExePath $QatDriverInstallArgs.HyperV.split()
                                              }
                                              } -ArgumentList $SetupExePath, $QatDriverInstallArgs, $UQMode | out-null
            } else {
                Invoke-Command -ScriptBlock {
                                              Param($SetupExePath, $QatDriverInstallArgs, $UQMode)
                                              if ($UQMode) {
                                                  &$SetupExePath $QatDriverInstallArgs.UQInstall.split()
                                              } else {
                                                  &$SetupExePath $QatDriverInstallArgs.Install.split()
                                              }
                                              } -ArgumentList $SetupExePath, $QatDriverInstallArgs, $UQMode | out-null
            }
        }
    } else {
        if ($Remote) {
            Invoke-Command -Session $Session -ScriptBlock {
                                                            Param($SetupExePath, $QatDriverInstallArgs)
                                                            &$SetupExePath $QatDriverInstallArgs.Uninstall.split()
                                                            } -ArgumentList $SetupExePath, $QatDriverInstallArgs | out-null
        } else {
            Invoke-Command -ScriptBlock {
                                          Param($SetupExePath, $QatDriverInstallArgs)
                                          &$SetupExePath $QatDriverInstallArgs.Uninstall.split()
                                          } -ArgumentList $SetupExePath, $QatDriverInstallArgs | out-null
        }
    }

    if ($Wait) {
        if ($Remote) {
            WBase-WaitProcessToCompletedByName -ProcessName "QatSetup" -Session $Session -Remote $true | out-null
        } else {
            WBase-WaitProcessToCompletedByName -ProcessName "QatSetup" -Remote $false | out-null
        }
    }

    # Handle uninstalling residues on Host: after
    if (!$Operation) {
        # Uninstall
        if (!$Remote) {
            # Remove uninstalling residues files
            WBaseHandleUninstallingResidues
        }
    }
}

function WBase-CheckDriverInstalled
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote = $false,

        [object]$Session
    )

    $returnValue = $false

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    $DriverInfo = WBaseGetDriverInfoFromRegedit `
        -Remote $Remote `
        -Session $Session

    if ([String]::IsNullOrEmpty($DriverInfo.DisplayName)) {
        Win-DebugTimestamp -output ("{0}: The QAT driver has not installed" -f $LogKeyWord)
        $returnValue = $false
    } else {
        Win-DebugTimestamp -output ("{0}: The QAT driver has installed" -f $LogKeyWord)
        $returnValue = $true
    }

    return $returnValue
}

function WBase-DoubleCheckDriver
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session
    )

    # Base on QAT driver installed
    $returnValue = $false

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    $IcpQatPackage = $null
    $IcpQatInstalled = $null
    $IcpQatInstalledPath = "C:\\Windows\\System32\\drivers"
    $VMVFDriverPath = "{0}\\{1}" -f $STVWinPath, $VMDriverInstallPath.InstallPath
    if ([String]::IsNullOrEmpty($LocationInfo.IcpQatName)) {
        $Key = "icp_qat*.sys"
    } else {
        $Key = "{0}.sys" -f $LocationInfo.IcpQatName
    }

    # Get IcpQat file on package
    if ($Remote) {
        $IcpQatFileArray = WBase-FindFiles `
            -Path $VMVFDriverPath `
            -Key $Key `
            -Remote $Remote `
            -Session $Session
    } else {
        $IcpQatFileArray = WBase-FindFiles `
            -Path $LocalPFDriverPath `
            -Key $Key `
            -Remote $Remote
    }

    if ([String]::IsNullOrEmpty($IcpQatFileArray)) {
        throw ("{0}: Can not get IcpQat file on package" -f $LogKeyWord)
    } else {
        if ([string]($IcpQatFileArray.gettype()) -eq "string") {
            $IcpQatPackage = $IcpQatFileArray
        } else {
            throw ("{0}: Get more IcpQat files on package > {1}" -f $LogKeyWord, $IcpQatFileArray.length)
        }
    }

    # Get IcpQat file on installed path
    if ($Remote) {
        $IcpQatFileArray = WBase-FindFiles `
            -Path $IcpQatInstalledPath `
            -Key $Key `
            -Remote $Remote `
            -Session $Session
    } else {
        $IcpQatFileArray = WBase-FindFiles `
            -Path $IcpQatInstalledPath `
            -Key $Key `
            -Remote $Remote
    }

    if ([String]::IsNullOrEmpty($IcpQatFileArray)) {
        throw ("{0}: Can not get IcpQat file on installed path" -f $LogKeyWord)
    } else {
        if ([string]($IcpQatFileArray.gettype()) -eq "string") {
            $IcpQatInstalled = $IcpQatFileArray
        } else {
            throw ("{0}: Get more IcpQat files on installed path > {1}" -f $LogKeyWord, $IcpQatFileArray.length)
        }
    }

    # Get IcpQat files MD5 value
    if ($Remote) {
        $IcpQatPackageMD5 = Invoke-Command -Session $Session -ScriptBlock {
            Param($IcpQatPackage)
            certutil -hashfile $IcpQatPackage MD5
        } -ArgumentList $IcpQatPackage
        $IcpQatInstalledMD5 = Invoke-Command -Session $Session -ScriptBlock {
            Param($IcpQatInstalled)
            certutil -hashfile $IcpQatInstalled MD5
        } -ArgumentList $IcpQatInstalled
    } else {
        $IcpQatPackageMD5 = certutil -hashfile $IcpQatPackage MD5
        $IcpQatInstalledMD5 = certutil -hashfile $IcpQatInstalled MD5
    }

    $IcpQatPackageMD5 = ($IcpQatPackageMD5).split("\n")[1]
    $IcpQatInstalledMD5 = ($IcpQatInstalledMD5).split("\n")[1]

    if ($IcpQatPackageMD5 -eq $IcpQatInstalledMD5) {
        $returnValue = $true
    } else {
        $returnValue = $false
    }

    if ($returnValue) {
        Win-DebugTimestamp -output (
            "{0}: Double check IcpQat file > passed" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Double check IcpQat file > failed" -f $LogKeyWord
        )
    }

    return $returnValue
}

# About test process
function WBase-WriteHashtableToJsonFile
{
    Param(
        [Parameter(Mandatory=$True)]
        [hashtable]$Info,

        [Parameter(Mandatory=$True)]
        [string]$InfoFilePath
    )

    if (Test-Path -Path $InfoFilePath) {
        Remove-Item `
            -Path $InfoFilePath `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    $Info | ConvertTo-Json -Depth 5 | Out-File $InfoFilePath -Encoding ascii

    return $InfoFilePath
}

function WBase-ReadHashtableFromJsonFile
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$InfoFilePath
    )

    $ReturnValue = $null

    $InfoFile = Get-Content -Path $InfoFilePath -Raw
    $ReturnValue = ConvertFrom-Json -InputObject $InfoFile -AsHashtable

    return $ReturnValue
}

function WBase-GenerateInfoFile
{
    Param(
        [hashtable]$Info = $null,

        [string]$InfoFilePath = $null
    )

    if ([String]::IsNullOrEmpty($Info)) {
        $Info = $global:LocationInfo
    }

    if ([String]::IsNullOrEmpty($InfoFilePath)) {
        $InfoFilePath = $global:LocalInfoFilePath
    }

    WBase-WriteHashtableToJsonFile `
        -Info $Info `
        -InfoFilePath $InfoFilePath | out-null

    return $InfoFilePath
}

function WBase-GetInfoFile
{
    Param(
        [string]$InfoFilePath = $null
    )

    $ReturnValue = $null

    if ([String]::IsNullOrEmpty($InfoFilePath)) {
        $InfoFilePath = $global:LocalInfoFilePath
    }

    $ReturnValue = WBase-ReadHashtableFromJsonFile -InfoFilePath $InfoFilePath
    $global:LocationInfo = $ReturnValue

    return $ReturnValue
}

function WBase-StartProcess
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ProcessFilePath,

        [Parameter(Mandatory=$True)]
        [string]$ProcessArgs,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [bool]$Remote = $false,

        [object]$Session = $null
    )

    $ReturnValue = [hashtable] @{
        ID = $null
        Output = $null
        Error = $null
        Result = $null
    }

    Win-DebugTimestamp -output ("Start process ---------------------- {0}" -f $keyWords)
    Win-DebugTimestamp -output ("{0}: Process file > {1}" -f $keyWords, $ProcessFilePath)
    Win-DebugTimestamp -output ("{0}: Process args > {1}" -f $keyWords, $ProcessArgs)

    $ScriptBlock = {
        Param(
            $ProcessFilePath,
            $ProcessArgs,
            $ProcessOutputLogPath,
            $ProcessErrorLogPath,
            $ProcessResultPath
        )

        $ReturnValue = $null

        if ($ProcessFilePath -eq "pwsh") {
            $ProcessCommandFilePath = "C:\Program Files\PowerShell\7\pwsh.exe"
            if (-not [System.IO.File]::Exists($ProcessCommandFilePath)) {
                $ProcessCommandFilePath = "powershell"
            }

            $ProcessCommandArgs = "-Command {0}" -f $ProcessArgs
        } else {
            $ProcessCommandFilePath = $ProcessFilePath
            $ProcessCommandArgs = $ProcessArgs
        }

        if (Test-Path -Path $ProcessOutputLogPath) {
            $OutputLogPath = Split-Path -Path $ProcessOutputLogPath
            $OutputLogName = Split-Path -Path $ProcessOutputLogPath -Leaf
            $OutputLogNameArray = $OutputLogName.split(".")
            for ($i = 0; $i -lt 1000; $i++) {
                $OutputLog = "{0}{1}-{2}.{3}" -f
                    $OutputLogPath,
                    $OutputLogNameArray[0],
                    $i,
                    $OutputLogNameArray[1]
                if (-not (Test-Path -Path $OutputLog)) {
                    break
                }
            }
            Copy-Item -Path $ProcessOutputLogPath -Destination $OutputLog | out-null
            Get-Item -Path $ProcessOutputLogPath | Remove-Item -Recurse -Force | out-null
        }

        if (Test-Path -Path $ProcessErrorLogPath) {
            $ErrorLogPath = Split-Path -Path $ProcessErrorLogPath
            $ErrorLogName = Split-Path -Path $ProcessErrorLogPath -Leaf
            $ErrorLogNameArray = $ErrorLogName.split(".")
            for ($i = 0; $i -lt 1000; $i++) {
                $ErrorLog = "{0}{1}-{2}.{3}" -f
                    $ErrorLogPath,
                    $ErrorLogNameArray[0],
                    $i,
                    $ErrorLogNameArray[1]
                if (-not (Test-Path -Path $ErrorLog)) {
                    break
                }
            }
            Copy-Item -Path $ProcessErrorLogPath -Destination $ErrorLog | out-null
            Get-Item -Path $ProcessErrorLogPath | Remove-Item -Recurse -Force | out-null
        }

        if (Test-Path -Path $ProcessResultPath) {
            $TestResultPath = Split-Path -Path $ProcessResultPath
            $TestResultName = Split-Path -Path $ProcessResultPath -Leaf
            $TestResultNameArray = $TestResultName.split(".")
            for ($i = 0; $i -lt 1000; $i++) {
                $TestResult = "{0}{1}-{2}.{3}" -f
                    $TestResultPath,
                    $TestResultNameArray[0],
                    $i,
                    $TestResultNameArray[1]
                if (-not (Test-Path -Path $TestResult)) {
                    break
                }
            }
            Copy-Item -Path $ProcessResultPath -Destination $TestResult | out-null
            Get-Item -Path $ProcessResultPath | Remove-Item -Recurse -Force | out-null
        }
        $ProcessResultName = Split-Path -Path $ProcessResultPath -Leaf
        $ProcessResultPathName = Split-Path -Path $ProcessResultPath
        New-Item -Path $ProcessResultPathName -Name $ProcessResultName -ItemType "file" | out-null

        $ProcessInfo = Start-Process -FilePath $ProcessCommandFilePath `
            -ArgumentList $ProcessCommandArgs `
            -RedirectStandardOutput $ProcessOutputLogPath `
            -RedirectStandardError $ProcessErrorLogPath `
            -NoNewWindow `
            -PassThru

        $GetProcessError = $null
        $ProcessOb = Get-Process `
            -ID $ProcessInfo.ID `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetProcessError
        if ([String]::IsNullOrEmpty($GetProcessError)) {
            $ReturnValue = [int]($ProcessInfo.ID)
        }

        return $ReturnValue
    }

    if ($Remote) {
        $ProcessOutputLogPath = "{0}\\{1}_Output.txt" -f
            $LocalProcessPath,
            $keyWords
        $ProcessErrorLogPath = "{0}\\{1}_Error.txt" -f
            $LocalProcessPath,
            $keyWords
        $ProcessResultPath = "{0}\\{1}_Result.json" -f
            $LocalProcessPath,
            $keyWords
        $ProcessID = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ProcessFilePath,
                          $ProcessArgs,
                          $ProcessOutputLogPath,
                          $ProcessErrorLogPath,
                          $ProcessResultPath
    } else {
        if ([String]::IsNullOrEmpty($WinTestProcessPath)) {
            $WinTestProcessPath = "{0}\\Process" -f $LocationInfo.BertaResultPath
        }

        if ([String]::IsNullOrEmpty($LocationInfo.TestCaseName)) {
            $ProcessOutputLogPath = "{0}\\{1}_Output.txt" -f
                $WinTestProcessPath,
                $keyWords
            $ProcessErrorLogPath = "{0}\\{1}_Error.txt" -f
                $WinTestProcessPath,
                $keyWords
            $ProcessResultPath = "{0}\\{1}_Result.json" -f
                $WinTestProcessPath,
                $keyWords
        } else {
            $ProcessOutputLogPath = "{0}\\{1}_{2}_Output.txt" -f
                $WinTestProcessPath,
                $LocationInfo.TestCaseName,
                $keyWords
            $ProcessErrorLogPath = "{0}\\{1}_{2}_Error.txt" -f
                $WinTestProcessPath,
                $LocationInfo.TestCaseName,
                $keyWords
            $ProcessResultPath = "{0}\\{1}_{2}_Result.json" -f
                $WinTestProcessPath,
                $LocationInfo.TestCaseName,
                $keyWords
        }
        $ProcessID = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ProcessFilePath,
                          $ProcessArgs,
                          $ProcessOutputLogPath,
                          $ProcessErrorLogPath,
                          $ProcessResultPath
    }

    $ReturnValue.ID = $ProcessID
    $ReturnValue.Output = $ProcessOutputLogPath
    $ReturnValue.Error = $ProcessErrorLogPath
    $ReturnValue.Result = $ProcessResultPath

    # Win-DebugTimestamp -output ("{0}: Process output file > {1}" -f $keyWords, $ReturnValue.Output)
    # Win-DebugTimestamp -output ("{0}: Process error file > {1}" -f $keyWords, $ReturnValue.Error)
    # Win-DebugTimestamp -output ("{0}: Process result file > {1}" -f $keyWords, $ReturnValue.Result)
    if ([String]::IsNullOrEmpty($ReturnValue.ID)) {
        Win-DebugTimestamp -output ("{0}: Can not get process id" -f $keyWords)
    } else {
        Win-DebugTimestamp -output ("{0}: Process id > {1}" -f $keyWords, $ReturnValue.ID)
    }

    return $ReturnValue
}

function WBase-CheckProcessNumber
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ProcessName,

        [int]$ProcessNumber = 1,

        [bool]$Remote = $false,

        [object]$Session = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $ProcessError = $null
        $ProcessValue = Invoke-Command -Session $Session -ScriptBlock {
            Param($ProcessName)
            $ReturnValue = [hashtable] @{
                error = $null
                result = $null
            }
            $ProcessError = $null
            $ProcessStatus = Get-Process -Name $ProcessName `
                                         -ErrorAction SilentlyContinue `
                                         -ErrorVariable ProcessError

            if ([String]::IsNullOrEmpty($ProcessError)) {
                $ReturnValue.result = $ProcessStatus
                $ReturnValue.error = $null
            } else {
                $ReturnValue.error = $ProcessError
                $ReturnValue.result = $null
            }
            return $ReturnValue
        } -ArgumentList $ProcessName

        $ProcessError = $ProcessValue.error
        $ProcessStatus = $ProcessValue.result
    } else {
        $LogKeyWord = "Host"
        $ProcessError = $null
        $ProcessStatus = Get-Process -Name $ProcessName `
                                     -ErrorAction SilentlyContinue `
                                     -ErrorVariable ProcessError
    }

    if ([String]::IsNullOrEmpty($ProcessError)) {
        $getProcessNumber = 0
        ForEach ($ProcessStatusEach in $ProcessStatus) {
            if ($ProcessStatusEach.Name -eq $ProcessName) {
                $getProcessNumber += 1
            }
        }

        Win-DebugTimestamp -output (
            "{0}: The {1} processes named '{2}' is working" -f
                $LogKeyWord,
                $getProcessNumber,
                $ProcessName
        )

        if ([int]($getProcessNumber) -eq $ProcessNumber) {
            $ReturnValue.result = $true
            $ReturnValue.error = "no_error"
        } else {
            $ReturnValue.result = $false
            $ReturnValue.error = "process_number_error"
        }
    } else {
        Win-DebugTimestamp -output (
            "{0}: No processes named '{1}' is working" -f
                $LogKeyWord,
                $ProcessName
        )
        $ReturnValue.result = $false
        $ReturnValue.error = "no_process_error"
    }

    return $ReturnValue
}

function WBase-WaitProcessToCompletedByName
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ProcessName,

        [bool]$Remote = $true,

        [object]$Session = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $ProcessError = $null
        $ProcessStatus = Invoke-Command -Session $Session -ScriptBlock {
            Param($ProcessName)
            Get-Process -Name $ProcessName 2>&1
        } -ArgumentList $ProcessName
    } else {
        $LogKeyWord = "Host"
        $ProcessError = $null
        $ProcessStatus = Get-Process -Name $ProcessName `
                                     -ErrorAction SilentlyContinue `
                                     -ErrorVariable ProcessError
    }

    if ([String]::IsNullOrEmpty($ProcessError)) {
        if (($ProcessStatus.length -ge 1) -and
            ($ProcessStatus[0].ProcessName -eq $ProcessName)) {
            Win-DebugTimestamp -output (
                "{0}: The '{1}' process is not completed and wait" -f
                    $LogKeyWord,
                    $ProcessName
            )
            if ($Remote) {
                $waitParcompStop = Invoke-Command -Session $Session -ScriptBlock {
                    Param($ProcessName)
                    wait-process -Name $ProcessName -Timeout 20000 2>&1
                    Start-Sleep -Seconds 5
                } -ArgumentList $ProcessName
            } else {
                $waitParcompStop = wait-process -Name $ProcessName -Timeout 20000 2>&1
                Start-Sleep -Seconds 5
            }

            if ($waitParcompStop -match "is not stopped in the specified time-out") {
                Win-DebugTimestamp -output (
                    "{0}: The '{1}' test is timeout" -f $LogKeyWord, $ProcessName
                )
                $ReturnValue.result = $false
                $ReturnValue.error = "process_timeout"
            }
        }
    }

    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: The '{1}' process is completed" -f $LogKeyWord, $ProcessName
        )
    }

    return $ReturnValue
}

function WBase-WaitProcessToCompletedByID
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$ProcessID,

        [bool]$Remote = $true,

        [object]$Session = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    $ProcessID | ForEach-Object {
        if ($Remote) {
            $ProcessError = $null
            $ProcessStatus = Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessID)
                Get-Process -ID $ProcessID 2>&1
            } -ArgumentList $_
        } else {
            $ProcessError = $null
            $ProcessStatus = Get-Process -ID $_ `
                                         -ErrorAction SilentlyContinue `
                                         -ErrorVariable ProcessError
        }

        if ([String]::IsNullOrEmpty($ProcessError)) {
            Win-DebugTimestamp -output (
                "{0}: The process({1}) is not completed and wait" -f $LogKeyWord, $_
            )

            if ($Remote) {
                $waitProcessStop = Invoke-Command -Session $Session -ScriptBlock {
                    Param($ProcessID)
                    wait-process -ID $ProcessID -Timeout 20000 2>&1
                    Start-Sleep -Seconds 5
                } -ArgumentList $_
            } else {
                $waitProcessStop = wait-process -ID $_ -Timeout 20000 2>&1
                Start-Sleep -Seconds 5
            }

            if ($waitParcompStop -match "is not stopped in the specified time-out") {
                Win-DebugTimestamp -output (
                    "{0}: The process({1}) is timeout" -f $LogKeyWord, $_
                )

                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "process_timeout"
                }
            }
        } else {
            Win-DebugTimestamp -output (
                "{0}: The process({1}) is completed" -f $LogKeyWord, $_
            )
        }
    }

    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: The all process is completed" -f $LogKeyWord
        )
    }

    return $ReturnValue
}

function WBase-CheckProcessOutput
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ProcessOutputLogPath,

        [Parameter(Mandatory=$True)]
        [string]$ProcessErrorLogPath,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [bool]$CheckResultFlag = $false,

        [string]$ProcessResultPath = $null,

        [string]$CheckResultType = "Base"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        process = [hashtable] @{
            output = $null
            error = $null
        }
        testResult = $null
        testcases = $null
    }

    # Check output and error log
    Win-DebugTimestamp -output (
        "{0}: Double check output log and error log of process({1})" -f
            $keyWords,
            $CheckResultType
    )

    $ScriptBlock = {
        Param($ProcessOutputLogPath, $ProcessErrorLogPath)

        $ReturnValue = [hashtable] @{
            result = $true
            error = "no_error"
            process = [hashtable] @{
                output = $null
                error = $null
            }
        }

        if (Test-Path -Path $ProcessOutputLogPath) {
            $ReturnValue.process.output = Get-Content -Path $ProcessOutputLogPath -Raw
        }

        if (Test-Path -Path $ProcessErrorLogPath) {
            $ReturnValue.process.error = Get-Content -Path $ProcessErrorLogPath -Raw
        }

        if ([String]::IsNullOrEmpty($ReturnValue.process.output)) {
            if ([String]::IsNullOrEmpty($ReturnValue.process.error)) {
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "no_output"
                }
            } else {
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "process_error"
                }
            }
        } else {
            if (-not [String]::IsNullOrEmpty($ReturnValue.process.error)) {
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "get_error"
                }
            }
        }

        return $ReturnValue
    }

    if ($Remote) {
        $ReturnValue = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ProcessOutputLogPath, $ProcessErrorLogPath
    } else {
        $ReturnValue = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ProcessOutputLogPath, $ProcessErrorLogPath
    }

    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: Double check result > passed" -f $keyWords
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Double check result > failed: {1}" -f $keyWords, $ReturnValue.error
        )
    }

    $CheckOutputLogFile = $ProcessOutputLogPath
    $CheckErrorLogFile = $ProcessErrorLogPath
    $CheckResultFile = $ProcessResultPath

    # Copy outputlog and errorlog files to BertaResultPath for remote
    if ($Remote) {
        if ([String]::IsNullOrEmpty($WinTestProcessPath)) {
            $WinTestProcessPath = "{0}\\Process" -f $LocationInfo.BertaResultPath
        }

        if ([String]::IsNullOrEmpty($LocationInfo.TestCaseName)) {
            $ProcessOutputLogPathName = Split-Path -Path $ProcessOutputLogPath -Leaf
            $ProcessErrorLogPathName = Split-Path -Path $ProcessErrorLogPath -Leaf
            if (-not [String]::IsNullOrEmpty($ProcessResultPath)) {
                $ProcessResultPathName = Split-Path -Path $ProcessResultPath -Leaf
            }
        } else {
            $ProcessOutputLogPathName = "{0}_{1}_Output.txt" -f
                $LocationInfo.TestCaseName,
                $keyWords
            $ProcessErrorLogPathName = "{0}_{1}_Error.txt" -f
                $LocationInfo.TestCaseName,
                $keyWords
            if (-not [String]::IsNullOrEmpty($ProcessResultPath)) {
                $ProcessResultPathName = "{0}_{1}_Result.json" -f
                    $LocationInfo.TestCaseName,
                    $keyWords
            }
        }

        $ProcessOutputLogDestination = "{0}\\{1}" -f
            $WinTestProcessPath,
            $ProcessOutputLogPathName
        if (Test-Path -Path $ProcessOutputLogDestination) {
            Remove-Item -Path $ProcessOutputLogDestination -Force | out-null
        }

        if (Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessOutputLogPath)
                Test-Path -Path $ProcessOutputLogPath
            } -ArgumentList $ProcessOutputLogPath) {
            Win-DebugTimestamp -output (
                "Copy output log file from '{0}' to '{1}'" -f
                    $ProcessOutputLogPath,
                    $ProcessOutputLogDestination
            )

            Copy-Item `
                -FromSession $Session `
                -Path $ProcessOutputLogPath `
                -Destination $ProcessOutputLogDestination `
                -Force `
                -Confirm:$false | out-null

            Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessOutputLogPath)
                Remove-Item -Path $ProcessOutputLogPath -Force | out-null
            } -ArgumentList $ProcessOutputLogPath
        }

        $ProcessErrorLogDestination = "{0}\\{1}" -f
            $WinTestProcessPath,
            $ProcessErrorLogPathName
        if (Test-Path -Path $ProcessErrorLogDestination) {
            Remove-Item -Path $ProcessErrorLogDestination -Force | out-null
        }

        if (Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessErrorLogPath)
                Test-Path -Path $ProcessErrorLogPath
            } -ArgumentList $ProcessErrorLogPath) {
            Win-DebugTimestamp -output (
                "Copy error log file from '{0}' to '{1}'" -f
                    $ProcessErrorLogPath,
                    $ProcessErrorLogDestination
            )

            Copy-Item `
                -FromSession $Session `
                -Path $ProcessErrorLogPath `
                -Destination $ProcessErrorLogDestination `
                -Force `
                -Confirm:$false | out-null

            Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessErrorLogPath)
                Remove-Item -Path $ProcessErrorLogPath -Force | out-null
            } -ArgumentList $ProcessErrorLogPath
        }

        if (-not [String]::IsNullOrEmpty($ProcessResultPath)) {
            $ProcessResultPathDestination = "{0}\\{1}" -f
                $WinTestProcessPath,
                $ProcessResultPathName
            if (Test-Path -Path $ProcessResultPathDestination) {
                Remove-Item -Path $ProcessResultPathDestination -Force | out-null
            }

            if (Invoke-Command -Session $Session -ScriptBlock {
                    Param($ProcessResultPath)
                    Test-Path -Path $ProcessResultPath
                } -ArgumentList $ProcessResultPath) {
                Win-DebugTimestamp -output (
                    "Copy result file from '{0}' to '{1}'" -f
                        $ProcessResultPath,
                        $ProcessResultPathDestination
                )

                Copy-Item `
                    -FromSession $Session `
                    -Path $ProcessResultPath `
                    -Destination $ProcessResultPathDestination `
                    -Force `
                    -Confirm:$false | out-null

                Invoke-Command -Session $Session -ScriptBlock {
                    Param($ProcessResultPath)
                    Remove-Item -Path $ProcessResultPath -Force | out-null
                } -ArgumentList $ProcessResultPath
            }
        }

        $CheckOutputLogFile = $ProcessOutputLogDestination
        $CheckErrorLogFile = $ProcessErrorLogDestination
        $CheckResultFile = $ProcessResultPathDestination
    }

    # Check test result
    if ($CheckResultFlag -and $ReturnValue.result) {
        Win-DebugTimestamp -output (
            "{0}: Double check test result log of process({1})" -f
                $keyWords,
                $CheckResultType
        )

        if ($CheckResultType -eq "Base") {
            if ([System.IO.File]::Exists($CheckResultFile)) {
                $ProcessResultHashtable = WBase-ReadHashtableFromJsonFile `
                    -InfoFilePath $CheckResultFile
                if ([String]::IsNullOrEmpty($ProcessResultHashtable)) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "no_test_result"
                } else {
                    $ReturnValue.result = $ProcessResultHashtable.result
                    $ReturnValue.error = $ProcessResultHashtable.error
                    $ReturnValue.testResult = $ProcessResultHashtable
                }
            } else {
                $ReturnValue.result = $false
                $ReturnValue.error = "no_result_file"
            }
        }

        if ($CheckResultType -eq "Gtest") {
            if ([System.IO.File]::Exists($CheckOutputLogFile)) {
                if ($Remote) {
                    $CheckResult = Gtest-GetTestCases `
                        -TestResultPath $CheckOutputLogFile `
                        -Remote $Remote `
                        -Session $Session
                } else {
                    $CheckResult = Gtest-GetTestCases `
                        -TestResultPath $CheckOutputLogFile `
                        -Remote $Remote
                }

                $ReturnValue.result = $CheckResult.result
                $ReturnValue.error = $CheckResult.error
                $ReturnValue.testcases = $CheckResult.testcases
            }
        }

        if ($ReturnValue.result) {
            Win-DebugTimestamp -output (
                "{0}: Double check result > passed" -f $keyWords
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: Double check result > failed: {1}" -f $keyWords, $ReturnValue.error
            )
        }
    }

    if ($ReturnValue.result) {
        <#
        Win-DebugTimestamp -output (
            "For more info, please double check output log > {0}" -f $CheckOutputLogFile
        )

        Win-DebugTimestamp -output (
            "For more info, please double check error log > {0}" -f $CheckErrorLogFile
        )
        #>
        Win-DebugTimestamp -output (
            "The process({0}) ---------------------- passed" -f $keyWords
        )
    } else {
        if (-not [String]::IsNullOrEmpty($ReturnValue.process.output)) {
            Win-DebugTimestamp -output (
                "{0}: The process >>>>> output >>>>> `r`n{1}" -f
                    $keyWords,
                    $ReturnValue.process.output
            )

            Win-DebugTimestamp -output (
                "{0}: The process >>>>> output end >>>>>" -f $keyWords
            )
        }

        if (-not [String]::IsNullOrEmpty($ReturnValue.process.error)) {
            Win-DebugTimestamp -output (
                "{0}: The process >>>>> error >>>>> `r`n{1}" -f
                    $keyWords,
                    $ReturnValue.process.error
            )

            Win-DebugTimestamp -output (
                "{0}: The process >>>>> error end >>>>>" -f $keyWords
            )
        }

        Win-DebugTimestamp -output (
            "The process({0}) ---------------------- failed > {1}" -f $keyWords, $ReturnValue.error
        )
    }

    return $ReturnValue
}

function WBase-WaitJobToCompleted
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$JobName,

        [int]$Timeout = 2000,

        [string]$LogKeyWord = "Host"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $JobError = $null
    $JobStatus = Get-Job `
        -Name $JobName `
        -ErrorAction SilentlyContinue `
        -ErrorVariable JobError

    if ([String]::IsNullOrEmpty($JobError)) {
        if ($JobStatus.State -eq "Running") {
            Win-DebugTimestamp -output (
                "{0}: The '{1}' job is not completed and wait" -f
                    $LogKeyWord,
                    $JobName
            )

            $WaitJobStop = Wait-Job -Name $JobName -Timeout $Timeout
            if ([String]::IsNullOrEmpty($WaitJobStop)) {
                Win-DebugTimestamp -output (
                    "{0}: The '{1}' job is timeout and stopped" -f
                        $LogKeyWord,
                        $JobName
                )

                Stop-Job -Name $JobName | out-null
                $ReturnValue.result = $false
                $ReturnValue.error = "job_timeout"
            }
        }

        if ($JobStatus.State -eq "Completed") {
            Win-DebugTimestamp -output (
                "{0}: The '{1}' job is completed" -f
                    $LogKeyWord,
                    $JobName
            )

            $ReturnValue.result = $true
            $ReturnValue.error = "no_error"
        } else {
            if ($ReturnValue.result) {
                $ReturnValue.result = $false
                $ReturnValue.error = "no_completed"
            }

            Win-DebugTimestamp -output (
                "{0}: The '{1}' job is not completed" -f
                    $LogKeyWord,
                    $JobName
            )
        }

        Remove-Job -Name $JobName -Force | out-null
    } else {
        Win-DebugTimestamp -output (
            "{0}: The '{1}' job is not exist" -f
                $LogKeyWord,
                $JobName
        )

        if ($JobError -match "cannot find the job") {
            $ReturnValue.result = $false
            $ReturnValue.error = "no_job"
        } else {
            $ReturnValue.result = $false
            $ReturnValue.error = "unknown_error"
        }
    }

    return $ReturnValue
}

# About test output
function WBase-CheckOutputLog
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$TestOutputLog,

        [Parameter(Mandatory=$True)]
        [string]$TestErrorLog,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [bool]$checkFIPSLog = $false,

        [object]$Session = $null,

        [string]$keyWords = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = $null
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name

        $TestOutputLog = Invoke-Command -Session $Session -ScriptBlock {
            Param($TestOutputLog)
            if (Test-Path -Path $TestOutputLog) {
                $ReturnValue = Get-Content -Path $TestOutputLog -Raw
            } else {
                $ReturnValue = $null
            }

            return $ReturnValue
        } -ArgumentList $TestOutputLog

        $TestErrorLog = Invoke-Command -Session $Session -ScriptBlock {
            Param($TestErrorLog)
            if (Test-Path -Path $TestErrorLog) {
                $ReturnValue = Get-Content -Path $TestErrorLog -Raw
            } else {
                $ReturnValue = $null
            }

            return $ReturnValue
        } -ArgumentList $TestErrorLog
    } else {
        $LogKeyWord = "Host"

        if (Test-Path -Path $TestOutputLog) {
            $TestOutputLog = Get-Content -Path $TestOutputLog -Raw
        } else {
            $TestOutputLog = $null
        }

        if (Test-Path -Path $TestErrorLog) {
            $TestErrorLog = Get-Content -Path $TestErrorLog -Raw
        } else {
            $TestErrorLog = $null
        }
    }

    Win-DebugTimestamp -output ("{0}: Double check test output log" -f $LogKeyWord)
    if ([String]::IsNullOrEmpty($TestOutputLog)) {
        Win-DebugTimestamp -output (
            "{0}: No test output log and double check test error log" -f $LogKeyWord
        )
        if ([String]::IsNullOrEmpty($TestErrorLog)) {
            Win-DebugTimestamp -output (
                "{0}: No test error log and double check dump file" -f $LogKeyWord
            )
            if ($Remote) {
                $DumpFileFlag = Invoke-Command -Session $Session -ScriptBlock {
                    Param($SiteKeep)
                    Test-Path -Path $SiteKeep.DumpFile
                } -ArgumentList $SiteKeep

            } else {
                $DumpFileFlag = Test-Path -Path $SiteKeep.DumpFile
            }

            if ($DumpFileFlag) {
                Win-DebugTimestamp -output ("{0}: This error is BSOD" -f $LogKeyWord)
                $ReturnValue.result = $false
                $ReturnValue.error = "BSOD_error"
            } else {
                Win-DebugTimestamp -output (
                    "{0}: This error is not BSOD and unknown error" -f $LogKeyWord
                )
                $ReturnValue.result = $false
                $ReturnValue.error = "unknown_error"
            }
        } else {
            Win-DebugTimestamp -output ("{0}: Error log > {1}" -f $LogKeyWord, $TestErrorLog)

            $ReturnValue.result = $false
            $ReturnValue.error = "process_error"
        }
    } else {
        $CheckOutputFlag = WBase-CheckOutputLogError -OutputLog $TestOutputLog -checkFIPSLog $checkFIPSLog
        if ($CheckOutputFlag) {
            if ([String]::IsNullOrEmpty($keyWords)) {
                Win-DebugTimestamp -output ("{0}: The test is passed" -f $LogKeyWord)
                $ReturnValue.result = $true
                $ReturnValue.error = "no_error"
            } else {
                $TestOps = WBase-GetTestOps -TestOut $TestOutputLog -keyWords $keyWords
                if ([String]::IsNullOrEmpty($TestOps) -or ($TestOps -eq "inf")) {
                    Win-DebugTimestamp -output ("{0}: Can not get Ops" -f $LogKeyWord)
                    Win-DebugTimestamp -output ("{0}: The test is failed" -f $LogKeyWord)
                    $ReturnValue.result = $false
                    $ReturnValue.error = "get_ops"
                } else {
                    Win-DebugTimestamp -output ("{0}: Getting Ops > {1}" -f $LogKeyWord, $TestOps)
                    Win-DebugTimestamp -output ("{0}: The test is passed" -f $LogKeyWord)
                    $ReturnValue.result = $true
                    $ReturnValue.error = "no_error"
                    $ReturnValue.testOps = $TestOps
                }
            }
        } else {
            $ReturnValue.result = $false
            $ReturnValue.error = "test_failed"
        }
    }

    return $ReturnValue
}

function WBase-CheckOutputLogError
{
    Param(
        [Parameter(Mandatory=$True)]
        [object]$OutputLog,

        [bool]$checkFIPSLog = $false
    )

    # Please check the output log file is not null at first
    $ReturnValue = $true

    $OutputLog | ForEach-Object {
        $_ = $_ -replace "\s{2,}", " "
        if($checkFIPSLog){
            if ($_ -ceq "Error") {
                $ReturnValue = $false
            }

            if ($_ -ceq "ERROR") {
                $ReturnValue = $false
            }
        }else{
            if ($_ -match "error") {
                $ReturnValue = $false
            }

            if ($_ -match "Error") {
                $ReturnValue = $false
            }

            if ($_ -match "ERROR") {
                $ReturnValue = $false
            }
        }

        if ($_ -match "Invalid") {
            $ReturnValue = $false
        }

        if ($_ -match "failed") {
            $ReturnValue = $false
        }
    }

    if (-not $ReturnValue) {
        Win-DebugTimestamp -output ("Get error in the output log > {0}" -f $OutputLog)
    }

    return $ReturnValue
}

function WBase-GetTestOps
{
    Param(
        [Parameter(Mandatory=$True)]
        [object]$TestOut,

        [Parameter(Mandatory=$True)]
        [string]$keyWords
    )

    $Ops = $null
    $TestOut = $TestOut.split("`r`n")
    $TestOut | ForEach-Object {
        $_ = $_ -replace "\s{2,}", " "
        if ($_ -match $keyWords) {
            $Ops = $_.split()[$_.split().count - 1]
        }
    }

    return [int]$Ops
}

function WBase-GetOutputFile
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$TestPath,

        [Parameter(Mandatory=$True)]
        [string]$FileName,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    # Need check type because:
    #    one return file will reset to hashtable
    #    more return files will return array
    $ReturnValue = @()

    $ScriptBlock = {
        Param($TestPath, $ParcompOpts)
        $ReturnValue = @()

        $TestParcompOutFileArray = Get-ChildItem -Path $TestPath
        $TestParcompOutFileArray | ForEach-Object {
            if (($_.Name -ne $ParcompOpts.OutputLog) -and
                ($_.Name -ne $ParcompOpts.ErrorLog) -and
                ($_.Name -ne $ParcompOpts.InputFileName)) {
                $ReturnValue += [hashtable] @{
                    name = $_.Name
                    path = $TestPath
                }
            }
        }

        return $ReturnValue
    }

    if ($Remote) {
        $OutputFileArray = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $TestPath, $ParcompOpts
    } else {
        $OutputFileArray = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $TestPath, $ParcompOpts
    }

    $OutputFileArray | ForEach-Object {
        if (-not [String]::IsNullOrEmpty($_.name)) {
            if ($_.name -match $FileName) {
                $ReturnValue += [hashtable] @{
                    name = $_.name
                    path = $_.path
                }
            }
        }
    }

    return $ReturnValue
}

function WBase-CheckOutputFile
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [bool]$deCompressFlag = $false,

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$Chunk = 64,

        [int]$blockSize = 4096,

        [string]$TestPath = $null,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.PathName
    }

    $TestSourceFile = "{0}\\{1}{2}.txt" -f $STVWinPath, $TestFileType, $TestFileSize
    $deCompressPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.MD5PathName
    $TestParcompOutFileList = @()
    $TestParcompOutFileMD5List = @()

    if ($Remote) {
        $VMNameSuffix = ($Session.Name).split("_")[1]
        $TestParcompOutFileArray = WBase-GetOutputFile `
            -TestPath $TestPath `
            -FileName $ParcompOpts.OutputFileName `
            -Remote $true `
            -Session $Session
    } else {
        $TestParcompOutFileArray = WBase-GetOutputFile `
            -TestPath $TestPath `
            -FileName $ParcompOpts.OutputFileName `
            -Remote $false
    }

    if ([String]::IsNullOrEmpty($TestParcompOutFileArray)) {
        $ReturnValue.result = $false
        $ReturnValue.error = "no_output_file"
        return $ReturnValue
    }

    # Init test files
    $ScriptBlock = {
        Param($TestParcompOutFileArray, $deCompressPath)
        $ReturnValue = [System.Array] @()

        if (Test-Path -Path $deCompressPath) {
            Get-Item -Path $deCompressPath | Remove-Item -Recurse -Force | out-null
        }
        New-Item -Path $deCompressPath -ItemType Directory | out-null

        $count = 0
        $TestParcompOutFileArray | ForEach-Object {
            $RundeCompressPath = "{0}\\deCompress_{1}" -f $deCompressPath, $count
            $count = $count + 1
            if (Test-Path -Path $RundeCompressPath) {
                Get-Item -Path $RundeCompressPath | Remove-Item -Recurse -Force | out-null
            }
            New-Item -Path $RundeCompressPath -ItemType Directory | out-null

            $ReturnValue += [hashtable] @{
                file = "{0}\\{1}" -f $_.path, $_.name
                path = $RundeCompressPath
            }
        }

        return $ReturnValue
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $TestParcompOutFileList = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $TestParcompOutFileArray, $deCompressPath

        $TestSourceFileMD5 = Invoke-Command -Session $Session -ScriptBlock {
            Param($TestSourceFile)
            certutil -hashfile $TestSourceFile MD5
        } -ArgumentList $TestSourceFile
        $TestSourceFileMD5 = $TestSourceFileMD5[1]

        if ($deCompressFlag) {
            ForEach ($TestParcompOutFile in $TestParcompOutFileList) {
                $TestParcompOutFileMD5 = Invoke-Command -Session $Session -ScriptBlock {
                    Param($TestParcompOutFile)
                    certutil -hashfile $TestParcompOutFile.file MD5
                } -ArgumentList $TestParcompOutFile
                $TestParcompOutFileMD5 = $TestParcompOutFileMD5[1]
                $TestParcompOutFileMD5List += $TestParcompOutFileMD5
            }
        }
    } else {
        $LogKeyWord = "Host"
        $TestParcompOutFileList = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $TestParcompOutFileArray, $deCompressPath

        $TestSourceFileMD5 = Invoke-Command -ScriptBlock {
            Param($TestSourceFile)
            certutil -hashfile $TestSourceFile MD5
        } -ArgumentList $TestSourceFile
        $TestSourceFileMD5 = $TestSourceFileMD5[1]

        if ($deCompressFlag) {
            ForEach ($TestParcompOutFile in $TestParcompOutFileList) {
                $TestParcompOutFileMD5 = Invoke-Command -ScriptBlock {
                    Param($TestParcompOutFile)
                    certutil -hashfile $TestParcompOutFile.file MD5
                } -ArgumentList $TestParcompOutFile
                $TestParcompOutFileMD5 = $TestParcompOutFileMD5[1]
                $TestParcompOutFileMD5List += $TestParcompOutFileMD5
            }
        }
    }

    if (-not $deCompressFlag) {
        if ($deCompressProvider -eq "7zip") {
            $TestParcompOutFileList = @()

            if (-not (Test-Path -Path $deCompressPath)) {
                New-Item -Path $deCompressPath -ItemType Directory | out-null
            }

            $count = 0
            $TestParcompOutFileArray | ForEach-Object {
                if ($Remote) {
                    $RundeCompressPath = "{0}\\{1}" -f $deCompressPath, $VMNameSuffix
                    if (-not (Test-Path -Path $deCompressPath)) {
                        New-Item -Path $deCompressPath -ItemType Directory | out-null
                    }

                    $RundeCompressPath = "{0}\\deCompress_{1}" -f $RundeCompressPath, $count
                } else {
                    $RundeCompressPath = "{0}\\deCompress_{1}" -f $deCompressPath, $count
                }

                if (-not (Test-Path -Path $RundeCompressPath)) {
                    New-Item -Path $RundeCompressPath -ItemType Directory | out-null
                }

                $count = $count + 1
                $TestParcompOutFile = "{0}\\{1}" -f $_.path, $_.name
                $deCompressInFile = "{0}\\{1}" -f $RundeCompressPath, $_.name
                if (Test-Path -Path $deCompressInFile) {
                    Remove-Item -Path $deCompressInFile -Force | out-null
                }

                if ($Remote) {
                    Copy-Item -FromSession $Session -Path $TestParcompOutFile -Destination $RundeCompressPath
                } else {
                    Copy-Item -Path $TestParcompOutFile -Destination $RundeCompressPath
                }

                $TestParcompOutFileList += [hashtable] @{
                    file = $deCompressInFile
                    path = $RundeCompressPath
                }
            }

            $count = 0
            ForEach ($TestParcompOutFile in $TestParcompOutFileList) {
                $TestdeCompressInFile = "{0}\\{1}" -f
                    $TestParcompOutFile.path,
                    $TestParcompOutFile.name
                $TestdeCompressOutFile = "{0}\\{1}" -f
                    $TestParcompOutFile.path,
                    ($ParcompOpts.OutputFileName).split(".")[0]
                if (Test-Path -Path $TestdeCompressOutFile) {
                    Get-Item -Path $TestdeCompressOutFile | Remove-Item -Recurse | out-null
                }

                $Use7zflag = UT-Use7z -InFile $TestdeCompressInFile -OutFile $TestParcompOutFile.path
                if ($Use7zflag) {
                    $TestdeCompressOutFileMD5 = certutil -hashfile $TestdeCompressOutFile MD5
                    $TestdeCompressOutFileMD5 = $TestdeCompressOutFileMD5[1]
                    $TestParcompOutFileMD5List += $TestdeCompressOutFileMD5
                } else {
                    if ($ReturnValue.result) {
                        $ReturnValue.result = $Use7zflag
                        $ReturnValue.error = "decompress_7zip_failed"
                    }
                }
            }
        } else {
            ForEach ($TestParcompOutFile in $TestParcompOutFileList) {
                if ($Remote) {
                    $TestFilelocation = "VM"
                } else {
                    $TestFilelocation = "host"
                }

                $deCompressProcess = WBase-Parcomp `
                    -Remote $Remote `
                    -Session $Session `
                    -deCompressFlag $true `
                    -CompressProvider $CompressProvider `
                    -deCompressProvider $deCompressProvider `
                    -QatCompressionType $QatCompressionType `
                    -Level $Level `
                    -Chunk $Chunk `
                    -blockSize $blockSize `
                    -numThreads 1 `
                    -numIterations 1 `
                    -TestPath $TestParcompOutFile.path `
                    -ParcompType "Fallback" `
                    -runParcompType "Process" `
                    -TestFilelocation $TestFilelocation `
                    -TestFilefullPath $TestParcompOutFile.file
            }

            WBase-WaitProcessToCompletedByName `
                -ProcessName "parcomp" `
                -Remote $Remote `
                -Session $Session | out-null

            ForEach ($TestParcompOutFile in $TestParcompOutFileList) {
                $TestdeCompressOutputLogFile = "{0}\\{1}" -f
                    $TestParcompOutFile.path,
                    $ParcompOpts.OutputLog
                $TestdeCompressErrorLogFile = "{0}\\{1}" -f
                    $TestParcompOutFile.path,
                    $ParcompOpts.ErrorLog

                if ($Remote) {
                    $CheckOutput = WBase-CheckOutputLog `
                        -TestOutputLog $TestdeCompressOutputLogFile `
                        -TestErrorLog $TestdeCompressErrorLogFile `
                        -Session $Session `
                        -Remote $true `
                        -keyWords "Mbps"
                    if ($CheckOutput.result) {
                        $TestParcompOutFileArray = WBase-GetOutputFile `
                            -TestPath $TestParcompOutFile.path `
                            -FileName $ParcompOpts.OutputFileName `
                            -Remote $true `
                            -Session $Session
                        $TestdeCompressOutFile = "{0}\\{1}" -f
                            $TestParcompOutFileArray.path,
                            $TestParcompOutFileArray.name
                        $TestdeCompressOutFileMD5 = Invoke-Command -Session $Session -ScriptBlock {
                            Param($TestdeCompressOutFile)
                            certutil -hashfile $TestdeCompressOutFile MD5
                        } -ArgumentList $TestdeCompressOutFile
                    } else {
                        $TestdeCompressOutFileMD5 = $CheckOutput.error
                    }
                } else {
                    $CheckOutput = WBase-CheckOutputLog `
                        -TestOutputLog $TestdeCompressOutputLogFile `
                        -TestErrorLog $TestdeCompressErrorLogFile `
                        -Remote $false `
                        -keyWords "Mbps"
                    if ($CheckOutput.result) {
                        $TestParcompOutFileArray = WBase-GetOutputFile `
                            -TestPath $TestParcompOutFile.path `
                            -FileName $ParcompOpts.OutputFileName `
                            -Remote $false
                        $TestdeCompressOutFile = "{0}\\{1}" -f
                            $TestParcompOutFileArray.path,
                            $TestParcompOutFileArray.name
                        $TestdeCompressOutFileMD5 = Invoke-Command -ScriptBlock {
                            Param($TestdeCompressOutFile)
                            certutil -hashfile $TestdeCompressOutFile MD5
                        } -ArgumentList $TestdeCompressOutFile
                    } else {
                        $TestdeCompressOutFileMD5 = $CheckOutput.error
                    }
                }

                $TestdeCompressOutFileMD5 = $TestdeCompressOutFileMD5[1]
                #Win-DebugTimestamp -output ("{0}: {1} > {2}" -f $Session.Name, $TestParcompOutFile, $TestParcompOutFileMD5)
                $TestParcompOutFileMD5List += $TestdeCompressOutFileMD5
            }
        }
    }

    $MD5MatchFlag = $true
    Win-DebugTimestamp -output (
        "{0}: The MD5 value of source file > {1}" -f
            $LogKeyWord,
            $TestSourceFileMD5
    )
    $FileCount = 0
    ForEach ($TestParcompOutFileMD5 in $TestParcompOutFileMD5List) {
        Win-DebugTimestamp -output (
            "{0}: The MD5 value of test output file {1} > {2}" -f
                $LogKeyWord,
                $FileCount,
                $TestParcompOutFileMD5
        )
        $FileCount++
        if ($TestParcompOutFileMD5 -ne $TestSourceFileMD5) {$MD5MatchFlag = $false}
    }
    if ($MD5MatchFlag) {
        Win-DebugTimestamp -output ("{0}: Those files are matched!" -f $LogKeyWord)
    } else {
        Win-DebugTimestamp -output ("{0}: Those files are not matched!" -f $LogKeyWord)
        $ReturnValue.result = $false
        $ReturnValue.error = "MD5_no_matched"
    }

    return $ReturnValue
}

# About Installer
function WBase-CheckQatDriver
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$Type,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [bool]$Operation = $true,

        [array]$QatDriverServices = ("icp_qat4"),

        [array]$QatDriverLibs = ("C:\\Program Files\\Intel\Intel(R) QuickAssist Technology\\Compression\\Library\\qatzip.lib"),

        [string]$QatDriverVersion = "2.0.0.0238"
    )

    $returnFlag = $true
    $LogKeyWord = $null
    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    if ($Type -eq "service") {
        Foreach ($QatDriverService in $QatDriverServices) {
            if ($Operation) {
                Win-DebugTimestamp -output ("{0}: After QAT driver installed, double check service > {1}" -f $LogKeyWord, $QatDriverService)
                if ($Remote) {
                    $out = Invoke-Command -Session $Session -ScriptBlock {
                        Param($QatDriverService)
                        (get-service -name $QatDriverService).Status
                    } -ArgumentList $QatDriverService
                } else {
                    $out = Invoke-Command -ScriptBlock {
                        Param($QatDriverService)
                        (get-service -name $QatDriverService).Status
                    } -ArgumentList $QatDriverService

                }

                if ([string]$out -eq "Running") {
                    Win-DebugTimestamp -output ("{0}: this service is running" -f $LogKeyWord)
                } else {
                    Win-DebugTimestamp -output ("{0}: this service is not running" -f $LogKeyWord)
                    $returnFlag = $false
                }
            } else {
                Win-DebugTimestamp -output ("{0}: After QAT driver uninstalled, double check service > {1}" -f $LogKeyWord, $QatDriverService)
                if ($Remote) {
                    $out = Invoke-Command -Session $Session -ScriptBlock {
                        Param($QatDriverService)
                        try {
                            get-service -name $QatDriverService 2>&1
                        } catch {
                        } finally {
                            get-service -name $QatDriverService 2>&1
                        }
                    } -ArgumentList $QatDriverService
                } else {
                    $out = Invoke-Command -ScriptBlock {
                        Param($QatDriverService)
                        try {
                            get-service -name $QatDriverService 2>&1
                        } catch {
                        } finally {
                            get-service -name $QatDriverService 2>&1
                        }
                    } -ArgumentList $QatDriverService
                }

                if ([string]$out -like "*Cannot find any service with*") {
                    Win-DebugTimestamp -output ("{0}: this service is deleted" -f $LogKeyWord)
                } else {
                    Win-DebugTimestamp -output ("{0}: this service is not deleted" -f $LogKeyWord)
                    $returnFlag = $false
                }
            }
        }
    } elseif ($Type -eq "device") {
        if ($Remote) {
            $out = Invoke-Command -Session $Session -ScriptBlock {
                Param($LocationInfo)
                (Get-PnpDevice -friendlyname $LocationInfo.friendlyname).Status
            } -ArgumentList $LocationInfo
        } else {
            $out = (Get-PnpDevice -friendlyname $LocationInfo.friendlyname).Status
        }

        $deviceCount = 0
        if ($out) {
            $out.split() | ForEach-Object {
                if ($_ -eq "OK") {$deviceCount += 1}
            }
        }

        if ($Operation) {
            Win-DebugTimestamp -output ("{0}: After QAT driver installed, double check device > {1}" -f $LogKeyWord, $deviceCount)
            if ($Remote) {
                if ($deviceCount -eq $LocationInfo.VF.Number) {
                    Win-DebugTimestamp -output ("{0}: The number of qat device is matched" -f $Session.Name)
                } else {
                    Win-DebugTimestamp -output ("{0}: The number of qat device is not matched" -f $Session.Name)
                    $returnFlag = $false
                }
            } else {
                if ($deviceCount -eq $LocationInfo.PF.Number) {
                    Win-DebugTimestamp -output ("Host: The number of qat device is matched")
                } else {
                    Win-DebugTimestamp -output ("Host: The number of qat device is not matched")
                    $returnFlag = $false
                }
            }
        } else {
            Win-DebugTimestamp -output ("{0}: After QAT driver uninstalled, double check device > {1}" -f $LogKeyWord, $deviceCount)
            if ($Remote) {
                if ($deviceCount -eq 0) {
                    Win-DebugTimestamp -output ("{0}: The number of qat device is matched" -f $Session.Name)
                } else {
                    Win-DebugTimestamp -output ("{0}: The number of qat device is not matched" -f $Session.Name)
                    $returnFlag = $false
                }
            } else {
                if ($deviceCount -eq 0) {
                    Win-DebugTimestamp -output ("Host: The number of qat device is matched")
                } else {
                    Win-DebugTimestamp -output ("Host: The number of qat device is not matched")
                    $returnFlag = $false
                }
            }
        }
    } elseif ($Type -eq "library") {
        Foreach ($QatDriverLib in $QatDriverLibs) {
            if ($Remote) {
                $out = Invoke-Command -Session $Session -ScriptBlock {
                    Param($QatDriverLib)
                    Test-Path -Path $QatDriverLib
                } -ArgumentList $QatDriverLib
            } else {
                $out = Test-Path -Path $QatDriverLib
            }

            if ($Operation) {
                Win-DebugTimestamp -output ("{0}: After QAT driver installed, double check library > {1}" -f $LogKeyWord, $QatDriverLib)
                if ($out) {
                    Win-DebugTimestamp -output ("{0}: The library is installed correctly" -f $LogKeyWord)
                } else {
                    Win-DebugTimestamp -output ("{0}: The library is installed incorrectly" -f $LogKeyWord)
                    $returnFlag = $false
                }
            } else {
                Win-DebugTimestamp -output ("{0}: After QAT driver uninstalled, double check library > {1}" -f $LogKeyWord, $QatDriverLib)
                if (!$out) {
                    Win-DebugTimestamp -output ("{0}: The library is deleted" -f $LogKeyWord)
                } else {
                    Win-DebugTimestamp -output ("{0}: The library is not deleted" -f $LogKeyWord)
                    $returnFlag = $false
                }
            }
        }
    } else {
        $returnFlag = $false
        throw ("Checking qat driver installer can not support this type > {0}" -f $Type)
    }

    Win-DebugTimestamp -output ("{0}: Installer checking is completed > {1}" -f $LogKeyWord, $returnFlag)

    return $returnFlag
}

# About performance test
function WBase-CheckTestOps
{
    Param(
        [Parameter(Mandatory=$True)]
        [int]$testOps,

        [Parameter(Mandatory=$True)]
        [string]$BanchMarkFile,

        [Parameter(Mandatory=$True)]
        [string]$testName
    )

    $ReturnValue = [hashtable] @{
        result = $false
        banckmarkOps = 10000
    }

    $BanchMarkFileName = Split-Path -Path $BanchMarkFile -Leaf
    $BanchMarkFilePath = Split-Path -Path $BanchMarkFile
    $BanchMarkFileNew = "{0}\\{1}" -f $LocationInfo.BertaResultPath, $BanchMarkFileName
    $threshold = 0.7

    if (Test-Path -Path $BanchMarkFile) {
        $BanchMarkList = Get-Content -Path $BanchMarkFile
        ForEach ($BanchMarkLine in $BanchMarkList) {
            $BanchMarkLine = ConvertFrom-Json -InputObject $BanchMarkLine -AsHashtable
            if ($BanchMarkLine.tc -eq $testName) {
                $ReturnValue.banckmarkOps = $BanchMarkLine.ops
                $ReturnValue.result = $true
            }
        }
    }

    if (-not $ReturnValue.result) {
        if (-not (Test-Path -Path $BanchMarkFileNew)) {
            if (Test-Path -Path $BanchMarkFile) {
                Copy-Item -Path $BanchMarkFile -Destination $BanchMarkFileNew
            } else {
                New-Item `
                    -Path $LocationInfo.BertaResultPath `
                    -Name $BanchMarkFileName `
                    -ItemType "file" | out-null
            }
        }

        $CurrentResult = [hashtable] @{
            tc = $testName
            ops = $testOps
        }
        WBase-WriteTestResult -TestResult $CurrentResult -ResultFile $BanchMarkFileNew
    }

    if ($testOps -ge [int]($ReturnValue.banckmarkOps * $threshold)) {
        $ReturnValue.result = $true
    } else {
        $ReturnValue.result = $false
        Win-DebugTimestamp -output (
            "Performance degradation > testOps:BanchMarkOps -- {0}:{1}" -f
                $testOps,
                $ReturnValue.banckmarkOps
        )
    }

    return $ReturnValue
}

# About SWFallback test
function WBase-CheckQatDevice
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [string]$CheckStatus = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        number = 0
        list = [System.Array] @()
    }

    for ($it = 0; $it -lt 20; $it++) {
        if ($Remote) {
            $CheckNumber = $LocationInfo.VF.Number
            $GetPnPResult = Invoke-Command -Session $Session -ScriptBlock {
                Param($LocationInfo)
                $ReturnValue = [hashtable] @{
                    result = [System.Array] @()
                    error = $null
                }

                $GetPnpError = $null
                $ReturnValue.result = Get-PnpDevice `
                    -friendlyname $LocationInfo.FriendlyName `
                    -PresentOnly `
                    -ErrorAction SilentlyContinue `
                    -ErrorVariable GetPnpError

                $ReturnValue.error = $GetPnpError

                return $ReturnValue
            } -ArgumentList $LocationInfo
        } else {
            $CheckNumber = $LocationInfo.PF.Number
            $GetPnPResult = Invoke-Command -ScriptBlock {
                Param($LocationInfo)
                $ReturnValue = [hashtable] @{
                    result = $true
                    error = $null
                }

                $GetPnpError = $null
                $ReturnValue.result = Get-PnpDevice `
                    -friendlyname $LocationInfo.FriendlyName `
                    -PresentOnly `
                    -ErrorAction SilentlyContinue `
                    -ErrorVariable GetPnpError

                $ReturnValue.error = $GetPnpError

                return $ReturnValue
            } -ArgumentList $LocationInfo
        }

        if ([String]::IsNullOrEmpty($GetPnPResult.error)) {
            $ReturnValue.list = $GetPnPResult.result
            $ReturnValue.list | ForEach-Object {
                if ([String]::IsNullOrEmpty($CheckStatus)) {
                    $ReturnValue.number += 1
                } else {
                    if ($_.Status -eq $CheckStatus) {
                        $ReturnValue.number += 1
                    }
                }
            }

            if ($ReturnValue.number -eq 0) {
                $ReturnValue.result = $false
            } else {
                if ($ReturnValue.number -ne $CheckNumber) {
                    $ReturnValue.result = $false
                }
            }

            if ($ReturnValue.result) {
                if ($Remote) {
                    Win-DebugTimestamp -output ("{0}: Double check VF device number is correct" -f $Session.Name)
                } else {
                    Win-DebugTimestamp -output ("Host: Double check PF device number is correct")
                }
            } else {
                if ($Remote) {
                    Win-DebugTimestamp -output ("{0}: Double check VF device number is incorrect" -f $Session.Name)
                } else {
                    Win-DebugTimestamp -output ("Host: Double check PF device number is incorrect")
                }
            }

            break
        } else {
            Win-DebugTimestamp -output ("Get PnP devices is error: {0}" -f $GetPnPResult.error)
            Win-DebugTimestamp -output ("Wait 10s and try again: {0}" -f ($it + 1))
            Start-Sleep -Seconds 10
        }
    }

    return $ReturnValue
}

function WBase-EnableAndDisableQatDevice
{
    Param(
        [bool]$Remote = $false,

        [object]$Session = $null,

        [bool]$Disable = $true,

        [bool]$Enable = $true,

        [bool]$Wait = $true
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    $ReturnValue = $true

    # disable qat device
    if ($Disable) {
        if ($Remote) {
            $CheckResult = WBase-CheckQatDevice `
                -Remote $Remote `
                -Session $Session `
                -CheckStatus "OK"
        } else {
            $CheckResult = WBase-CheckQatDevice `
                -Remote $Remote `
                -CheckStatus "OK"
        }

        Win-DebugTimestamp -output (
            "{0}: The number of qat device that need to disable > {1}" -f
                $LogKeyWord,
                $CheckResult.number
        )

        if ($CheckResult.result) {
            $CheckResult.list | ForEach-Object {
                Win-DebugTimestamp -output (
                    "{0}: Disable qat device > {1}" -f $LogKeyWord, $_.InstanceId
                )

                if ($Remote) {
                    $PNPOperationResult = Invoke-Command -Session $Session -ScriptBlock {
                        Param($_)
                        $PNPdeviceJob = Start-Job -ScriptBlock {
                            Param($_)
                            Disable-PnpDevice -InstanceId $_.InstanceId -confirm:$false
                        } -ArgumentList $_

                        $PNPdeviceJob | Wait-Job -Timeout 600
                        if ($PNPdeviceJob.State -ne "Completed") {
                            $PNPdeviceJob | Stop-Job | Remove-Job
                            return $false
                        }

                        $PNPDevice = Get-PnpDevice -InstanceId $_.InstanceId
                        if ($PNPDevice.Status -eq "Error") {
                            return $true
                        } else {
                            return $false
                        }
                    } -ArgumentList $_
                } else {
                    $PNPOperationResult = $false
                    $PNPdeviceJob = Start-Job -ScriptBlock {
                        Param($_)
                        Disable-PnpDevice -InstanceId $_.InstanceId -confirm:$false
                    } -ArgumentList $_

                    $PNPdeviceJob | Wait-Job -Timeout 600 | out-null

                    if ($PNPdeviceJob.State -ne "Completed") {
                        $PNPdeviceJob | Stop-Job | Remove-Job | out-null
                        $PNPOperationResult = $false
                    } else {
                        $PNPOperationResult = $true
                    }

                    $PNPDevice = Get-PnpDevice -InstanceId $_.InstanceId
                    if ($PNPDevice.Status -eq "Error") {
                        $PNPOperationResult = $true
                    } else {
                        $PNPOperationResult = $false
                    }
                }

                if (-not $PNPOperationResult) {
                    Win-DebugTimestamp -output ("{0}: Disable qat device is failed" -f $LogKeyWord)
                    if ($ReturnValue) {
                        $ReturnValue = $false
                    }
                }
            }

            if ($Wait) {
                Start-Sleep -Seconds 5
            }
        } else {
            Win-DebugTimestamp -output (
                "{0}: The number of qat device is incorrect, skp disable operation" -f $LogKeyWord
            )

            if ($ReturnValue) {
                $ReturnValue = $false
            }
        }
    }

    # enable qat device
    if ($Enable) {
        if ($Remote) {
            $CheckResult = WBase-CheckQatDevice `
                -Remote $Remote `
                -Session $Session `
                -CheckStatus "Error"
        } else {
            $CheckResult = WBase-CheckQatDevice `
                -Remote $Remote `
                -CheckStatus "Error"
        }

        Win-DebugTimestamp -output (
            "{0}: The number of qat device that need to enable > {1}" -f
                $LogKeyWord,
                $CheckResult.number
        )

        if ($CheckResult.result) {
            $CheckResult.list | ForEach-Object {
                Win-DebugTimestamp -output (
                    "{0}: Enable qat device > {1}" -f $LogKeyWord, $_.InstanceId
                )

                if ($Remote) {
                    $PNPOperationResult = Invoke-Command -Session $Session -ScriptBlock {
                        Param($_)
                        $PNPdeviceJob = Start-Job -ScriptBlock {
                            Param($_)
                            Enable-PnpDevice -InstanceId $_.InstanceId -confirm:$false
                        } -ArgumentList $_

                        $PNPdeviceJob | Wait-Job -Timeout 600
                        if ($PNPdeviceJob.State -ne "Completed") {
                            $PNPdeviceJob | Stop-Job | Remove-Job
                            return $false
                        }

                        $PNPDevice = Get-PnpDevice -InstanceId $_.InstanceId
                        if ($PNPDevice.Status -eq "OK") {
                            return $true
                        } else {
                            return $false
                        }
                    } -ArgumentList $_
                } else {
                    $PNPOperationResult = $false
                    $PNPdeviceJob = Start-Job -ScriptBlock {
                        Param($_)
                        Enable-PnpDevice -InstanceId $_.InstanceId -confirm:$false
                    } -ArgumentList $_

                    $PNPdeviceJob | Wait-Job -Timeout 600 | out-null

                    if ($PNPdeviceJob.State -ne "Completed") {
                        $PNPdeviceJob | Stop-Job | Remove-Job | out-null
                        $PNPOperationResult = $false
                    } else {
                        $PNPOperationResult = $true
                    }

                    $PNPDevice = Get-PnpDevice -InstanceId $_.InstanceId
                    if ($PNPDevice.Status -eq "OK") {
                        $PNPOperationResult = $true
                    } else {
                        $PNPOperationResult = $false
                    }
                }

                if (-not $PNPOperationResult) {
                    Win-DebugTimestamp -output ("{0}: Enable qat device is failed" -f $LogKeyWord)
                    if ($ReturnValue) {
                        $ReturnValue = $false
                    }
                }
            }

            if ($Wait) {
                Start-Sleep -Seconds 30
            }
        } else {
            Win-DebugTimestamp -output (
                "{0}: The number of qat device is incorrect, skp enable operation" -f $LogKeyWord
            )

            if ($ReturnValue) {
                $ReturnValue = $false
            }
        }
    }

    return $ReturnValue
}

function WBase-HeartbeatQatDevice
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$LogPath
    )

    $ReturnValue = $true

    $CheckNumberResult = WBase-CheckQatDevice `
        -Remote $false `
        -CheckStatus "OK"

    if ($CheckNumberResult.result) {
        UT-TraceLogStart -Remote $false | out-null

        $HeartbeatTimes = 1
        Win-DebugTimestamp -output ("Will heartbeat qat device {0} times" -f $HeartbeatTimes)
        for ($it = 0; $it -lt $HeartbeatTimes; $it++) {
            Win-DebugTimestamp -output ("The time of heartbeat qat device > {0}" -f ($it + 1))
            for ($i = 0; $i -lt $LocationInfo.PF.Number; $i++) {
                Win-DebugTimestamp -output ("Query qat device > {0}" -f $i)
                $AdfCtlArgs = ("query {0}" -f $i)
                $AdfCtlOut = &$AdfCtlExe $AdfCtlArgs.split()

                if ($AdfCtlOut.split() -contains "failed") {
                    Win-DebugTimestamp -output ("Query qat device is failed > {0}" -f $AdfCtlOut)
                    continue
                }

                Win-DebugTimestamp -output ("Heartbeat qat device > {0}" -f $i)
                $AdfCtlArgs = ("heartbeat {0}" -f $i)
                $AdfCtlOut = &$AdfCtlExe $AdfCtlArgs.split()

                if (($AdfCtlOut) -and ($AdfCtlOut.split() -contains "failed")) {
                    Win-DebugTimestamp -output ("Heartbeat qat device is failed > {0}" -f $AdfCtlOut)
                    if ($ReturnValue) {
                        $ReturnValue = $false
                    }
                }

                Start-Sleep -Seconds 30
            }

            Start-Sleep -Seconds 60
        }

        if ($ReturnValue) {
            $ReturnValue = UT-TraceLogCheck
        }

        if ($ReturnValue) {
            $CheckNumberResult = WBase-CheckQatDevice `
                -Remote $false `
                -CheckStatus "OK"

            $ReturnValue = $CheckNumberResult.result
        }

        Win-DebugTimestamp -output ("Heartbeat qat device is completed")
    } else {
        Win-DebugTimestamp -output ("The number of qat device is incorrect, skip heartbeat operation")
        if ($ReturnValue) {
            $ReturnValue = $false
        }
    }

    return $ReturnValue
}

function WBase-UpgradeQatDevice
{
    $ReturnValue = $true

    if ($LocationInfo.HVMode) {
        # remove the QAT VF's
        $LocationInfo.VM.NameArray | ForEach-Object {
            $vmName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            HV-AssignableDeviceRemove -VMName $VMName | out-null
        }
    }

    Win-DebugTimestamp -output ("Uninstall Qat driver on local host: {0}" -f $LocationInfo.PF.DriverExe)
    WBase-InstallAndUninstallQatDriver -SetupExePath $LocationInfo.PF.DriverExe `
                                       -Operation $false `
                                       -Remote $false

    $CheckDriverResult = WBase-CheckDriverInstalled -Remote $false
    if ($CheckDriverResult) {
        if ($ReturnValue) {
            $ReturnValue = $false
        }
    }

    Win-DebugTimestamp -output ("Install Qat driver on local host: {0}" -f $LocationInfo.PF.DriverExe)
    WBase-InstallAndUninstallQatDriver -SetupExePath $LocationInfo.PF.DriverExe `
                                       -Operation $true `
                                       -Remote $false `
                                       -UQMode $LocationInfo.UQMode

    $CheckDriverResult = WBase-CheckDriverInstalled -Remote $false
    if (-not $CheckDriverResult) {
        if ($ReturnValue) {
            $ReturnValue = $false
        }
    }

    $DisableDeviceFlag = $false
    $UQModeStatus = UT-CheckUQMode `
        -CheckFlag $LocationInfo.UQMode `
        -Remote $false
    if (-not $UQModeStatus) {
        $DisableDeviceFlag = $true
        UT-SetUQMode `
            -UQMode $LocationInfo.UQMode `
            -Remote $false | out-null
    }

    UT-WorkAround `
        -Remote $false `
        -DisableFlag $DisableDeviceFlag | out-null

    $CheckNumberResult = WBase-CheckQatDevice `
        -Remote $false `
        -CheckStatus "OK"
    if (-not $CheckNumberResult.result) {
        if ($ReturnValue) {
            $ReturnValue = $false
        }
    }

    if ($LocationInfo.HVMode) {
        # re-Add the QAT VF's
        $LocationInfo.VM.NameArray | ForEach-Object {
            $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $PSSessionName = ("Session_{0}" -f $_)
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $LocationInfo.VM.IsWin

            HV-AssignableDeviceAdd `
                -VMName $VMName `
                -PFVFArray $LocationInfo.VF.PFVFList[$_] | out-null
            $CheckStatus = HV-AssignableDeviceCheck `
                -VMName $VMName `
                -PFVFArray $LocationInfo.VF.PFVFList[$_]
            if (-not $CheckStatus) {
                if ($ReturnValue) {
                    $ReturnValue = $false
                }
            }
        }

        Start-Sleep -Seconds 30

        $LocationInfo.VM.NameArray | ForEach-Object {
            $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $_)
            $PSSessionName = ("Session_{0}" -f $_)
            $Session = HV-PSSessionCreate `
                -VMName $VMName `
                -PSName $PSSessionName `
                -IsWin $LocationInfo.VM.IsWin

            $CheckNumberResult = WBase-CheckQatDevice `
                -Remote $true `
                -Session $Session `
                -CheckStatus "OK"
            if (-not $CheckNumberResult.result) {
                if ($ReturnValue) {
                    $ReturnValue = $false
                }
            }
        }
    }

    return $ReturnValue
}

# About parcomp tool
function WBase-GenerateParcompTestCase
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$ArrayProvider,

        [Parameter(Mandatory=$True)]
        [array]$ArrayChunk,

        [Parameter(Mandatory=$True)]
        [array]$ArrayBlock,

        [Parameter(Mandatory=$True)]
        [array]$ArrayCompressType,

        [Parameter(Mandatory=$True)]
        [array]$ArrayCompressionType,

        [Parameter(Mandatory=$True)]
        [array]$ArrayCompressionLevel,

        [Parameter(Mandatory=$True)]
        [array]$ArrayIteration,

        [Parameter(Mandatory=$True)]
        [array]$ArrayThread,

        [Parameter(Mandatory=$True)]
        [array]$ArrayTestFileType,

        [Parameter(Mandatory=$True)]
        [array]$ArrayTestFileSize
    )

    # $ReturnValue += [hashtable] @{
    #     Provider = "qat"
    #     Chunk = 64
    #     Block = 4096
    #     CompressType = "All"
    #     CompressionLevel = 1
    #     CompressionType = "dynamic"
    #     Iteration = 200
    #     Thread = 8
    #     TestFileType = "calgary"
    #     TestFileSize = 200
    # }
    $ReturnValue = [System.Array] @()

    Foreach ($TestFileType in $ArrayTestFileType) {
        Foreach ($TestFileSize in $ArrayTestFileSize) {
            Foreach ($Provider in $ArrayProvider) {
                Foreach ($Chunk in $ArrayChunk) {
                    Foreach ($CompressType in $ArrayCompressType) {
                        Foreach ($Iteration in $ArrayIteration) {
                            Foreach ($Thread in $ArrayThread) {
                                Foreach ($Block in $ArrayBlock) {
                                    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
                                        Foreach ($CompressionLevel in $ArrayCompressionLevel) {
                                            if ($Provider -eq "qat") {
                                                Foreach ($CompressionType in $ArrayCompressionType) {
                                                    $ReturnValue += [hashtable] @{
                                                        Provider = $Provider
                                                        Chunk = $Chunk
                                                        Block = $Block
                                                        CompressType = $CompressType
                                                        CompressionLevel = $CompressionLevel
                                                        CompressionType = $CompressionType
                                                        Iteration = $Iteration
                                                        Thread = $Thread
                                                        TestFileType = $TestFileType
                                                        TestFileSize = $TestFileSize
                                                    }
                                                }
                                            } else {
                                                $ReturnValue += [hashtable] @{
                                                    Provider = $Provider
                                                    Chunk = $Chunk
                                                    Block = $Block
                                                    CompressType = $CompressType
                                                    CompressionLevel = $CompressionLevel
                                                    CompressionType = "dynamic"
                                                    Iteration = $Iteration
                                                    Thread = $Thread
                                                    TestFileType = $TestFileType
                                                    TestFileSize = $TestFileSize
                                                }
                                            }
                                        }
                                    } else {
                                        if ($Provider -eq "qat") {
                                            Foreach ($CompressionType in $ArrayCompressionType) {
                                                $ReturnValue += [hashtable] @{
                                                    Provider = $Provider
                                                    Chunk = $Chunk
                                                    Block = $Block
                                                    CompressType = $CompressType
                                                    CompressionLevel = 1
                                                    CompressionType = $CompressionType
                                                    Iteration = $Iteration
                                                    Thread = $Thread
                                                    TestFileType = $TestFileType
                                                    TestFileSize = $TestFileSize
                                                }
                                            }
                                        } else {
                                            $ReturnValue += [hashtable] @{
                                                Provider = $Provider
                                                Chunk = $Chunk
                                                Block = $Block
                                                CompressType = $CompressType
                                                CompressionLevel = 1
                                                CompressionType = "dynamic"
                                                Iteration = $Iteration
                                                Thread = $Thread
                                                TestFileType = $TestFileType
                                                TestFileSize = $TestFileSize
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return $ReturnValue
}

function WBase-Parcomp
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [bool]$deCompressFlag = $false,

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$numThreads = 6,

        [int]$numIterations = 200,

        [int]$blockSize = 4096,

        [int]$Chunk = 64,

        [string]$ParcompType = "Base",

        [string]$runParcompType = "Base",

        [string]$TestFilelocation = "Host",

        [string]$TestFilefullPath = $null,

        [string]$TestPath = $null,

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200
    )

    # For deCompress operation: the TestFilefullPath must be compressed file
    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = $null
        job = $null
        process = $null
    }

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.PathName
    }

    $TestSourceFile = "{0}\\{1}{2}.txt" -f
        $STVWinPath,
        $TestFileType,
        $TestFileSize

    if ($Remote) {
        $LogKeyWord = $Session.Name
        Invoke-Command -Session $Session -ScriptBlock {
            Param($TestPath)
            if (Test-Path -Path $TestPath) {
                Get-Item -Path $TestPath | Remove-Item -Recurse
            }
            New-Item -Path $TestPath -ItemType Directory
        } -ArgumentList $TestPath | out-null

    } else {
        $LogKeyWord = "Host"

        if (Test-Path -Path $TestPath) {
            Get-Item -Path $TestPath | Remove-Item -Recurse
        }
        New-Item -Path $TestPath -ItemType Directory
    }

    $ParcompExe = "{0}\\{1}" -f $ParcompOpts.ParcompPath, $ParcompOpts.ParcompExeName
    $TestParcompInFile = "{0}\\{1}" -f $TestPath, $ParcompOpts.InputFileName
    $TestParcompOutFile = "{0}\\{1}" -f $TestPath, $ParcompOpts.OutputFileName
    $TestParcompOutLog = "{0}\\{1}" -f $TestPath, $ParcompOpts.OutputLog
    $TestParcompErrorLog = "{0}\\{1}" -f $TestPath, $ParcompOpts.ErrorLog
    $TestFileSizeBytes = $TestFileSize * 1024 * 1024

    # Get test source file
    if ($TestFilefullPath) {
        if ($Remote) {
            if ($TestFilelocation -eq "Host") {
                $TestFileName = Split-Path -Path $TestFilefullPath -Leaf
                $TestSourceFile = "{0}\\{1}" -f $STVWinPath, $TestFileName
                Win-DebugTimestamp -output (
                    "{0}: Copy source file from appoint test file: {1} -> {2}" -f
                        $PSSessionName,
                        $TestFilefullPath,
                        $TestSourceFile
                )
                Copy-Item `
                    -ToSession $Session `
                    -Path $TestFilefullPath `
                    -Destination $TestSourceFile

                $TestFilefullPath = $TestSourceFile
            }
        }

        if ($TestFilefullPath -ne $TestSourceFile) {
            $TestSourceFile = $TestFilefullPath
        }

        Win-DebugTimestamp -output (
            "{0}: Appoint test file as source file: {1}" -f
                $LogKeyWord,
                $TestSourceFile
        )
    } else {
        if ($Remote) {
            if (!(Invoke-Command -Session $Session -ScriptBlock {
                    Param($TestSourceFile)
                    Test-Path -Path $TestSourceFile
                } -ArgumentList $TestSourceFile))
            {
                WBase-CreateTestFile -Remote $true `
                                     -TestFileType $TestFileType `
                                     -TestFileSize $TestFileSize `
                                     -Session $Session
            }
        } else {
            if (!(Test-Path -Path $TestSourceFile)) {
                WBase-CreateTestFile -Remote $false `
                                     -TestFileType $TestFileType `
                                     -TestFileSize $TestFileSize
            }
        }
    }

    # Get input file of parcomp
    Win-DebugTimestamp -output (
        "{0}: Copy test file from source file: {1} -> {2}" -f
            $LogKeyWord,
            $TestSourceFile,
            $TestParcompInFile
    )
    if (($deCompressFlag) -and (!$TestFilefullPath)) {
        $ParcompArges = "-i {0} -o {1} -p {2} -c {3} -k {4} -FB" -f
            $TestSourceFile,
            $TestParcompInFile,
            $deCompressProvider,
            $Chunk,
            $blockSize
        if ($Remote) {
            Invoke-Command -Session $Session -ScriptBlock {
                Param($ParcompExe, $ParcompArges)
                &$ParcompExe $ParcompArges.split()
            } -ArgumentList $ParcompExe, $ParcompArges | out-null

            $CompressOutFileArray = WBase-GetOutputFile `
                -TestPath $TestPath `
                -FileName $ParcompOpts.InputFileName `
                -Remote $true `
                -Session $Session
            Invoke-Command -Session $Session -ScriptBlock {
                Param($CompressOutFile, $TestParcompInFile)
                if ($CompressOutFile.name -ne $TestParcompInFile) {
                    $FullPath = "{0}\\{1}" -f $CompressOutFile.path, $CompressOutFile.name
                    Rename-Item `
                        -Path $FullPath `
                        -NewName $TestParcompInFile | out-null
                }
            } -ArgumentList $CompressOutFileArray, $ParcompOpts.InputFileName | out-null
        } else {
            Invoke-Command -ScriptBlock {
                Param($ParcompExe, $ParcompArges)
                &$ParcompExe $ParcompArges.split()
            } -ArgumentList $ParcompExe, $ParcompArges | out-null

            $CompressOutFileArray = WBase-GetOutputFile `
                -TestPath $TestPath `
                -FileName $ParcompOpts.InputFileName `
                -Remote $false

            Invoke-Command -ScriptBlock {
                Param($CompressOutFile, $TestParcompInFile)
                if ($CompressOutFile.name -ne $TestParcompInFile) {
                    $FullPath = "{0}\\{1}" -f $CompressOutFile.path, $CompressOutFile.name
                    Rename-Item `
                        -Path $FullPath `
                        -NewName $TestParcompInFile | out-null
                }
            } -ArgumentList $CompressOutFileArray, $ParcompOpts.InputFileName | out-null
        }
    } else {
        if ($Remote) {
            Invoke-Command -Session $Session -ScriptBlock {
                Param($TestSourceFile, $TestParcompInFile)
                Copy-Item -Path $TestSourceFile -Destination $TestParcompInFile
            } -ArgumentList $TestSourceFile, $TestParcompInFile | out-null
        } else {
            Copy-Item -Path $TestSourceFile -Destination $TestParcompInFile
        }
    }

    $ParcompArges = "-i {0} -o {1} -c {2} -k {3}" -f
        $TestParcompInFile,
        $TestParcompOutFile,
        $Chunk,
        $blockSize
    if ($deCompressFlag) {
        $ParcompArges += " -d"
        $ParcompProvider = $deCompressProvider
    } else {
        $ParcompArges += " -l {0}" -f $Level
        $ParcompProvider = $CompressProvider
    }

    if ($ParcompProvider -eq "qat") {
        if ($QatCompressionType -eq "dynamic") {
            $ParcompArges += " -D"
        } else {
            $ParcompArges += " -s"
        }

        $ParcompArges += " -p qat"
    } elseif ($ParcompProvider -eq "qatzlib") {
        $ParcompArges += " -p qatzlib"
    } elseif ($ParcompProvider -eq "qatgzip") {
        $ParcompArges += " -p qatgzip"
    } elseif ($ParcompProvider -eq "qatgzipext") {
        $ParcompArges += " -p qatgzipext"
    } elseif ($ParcompProvider -eq "igzip") {
        $ParcompArges += " -p igzip"
    } elseif ($ParcompProvider -eq "qatlz4") {
        $ParcompArges += " -p qatlz4"
    } else {
        Win-DebugTimestamp -output (
            "{0}: Not support compress provider > {1}" -f $LogKeyWord, $ParcompProvider
        )
        $ReturnValue.result = $false
        $ReturnValue.error = ("provider_{0}" -f $ParcompProvider)
        return $ReturnValue
    }

    # Fallback test base on performance test
    if (($ParcompType -eq "Performance") -or ($ParcompType -eq "Fallback")) {
        $ParcompArges += " -Q -t {0} -n {1}" -f
            $numThreads,
            $numIterations
    }

    if ($ParcompType -eq "Fallback") {
        $ParcompArges += " -FB"
    }

    Win-DebugTimestamp -output (
        "{0}: Parcomp test > {1} {2}" -f $LogKeyWord, $ParcompExe, $ParcompArges
    )
    if ($runParcompType -eq "Base") {
        # After running this parcomp type, must be check:
        # -parcomp output log
        # -parcomp output file
        if ($Remote) {
            $ParcompPSOut = Invoke-Command -Session $Session -ScriptBlock {
                Param($ParcompExe, $ParcompArges)
                &$ParcompExe $ParcompArges.split()
            } -ArgumentList $ParcompExe, $ParcompArges
        } else {
            $ParcompPSOut = Invoke-Command -ScriptBlock {
                Param($ParcompExe, $ParcompArges)
                &$ParcompExe $ParcompArges.split()
            } -ArgumentList $ParcompExe, $ParcompArges
        }

        Win-DebugTimestamp -output (
            "{0}: Check output log of the parcomp test ({1})" -f
                $LogKeyWord,
                $runParcompType
        )

        if ([String]::IsNullOrEmpty($ParcompPSOut)) {
            $ReturnValue.result = $false
            $ReturnValue.error = "no_output"
        } else {
            $CheckOutputFlag = WBase-CheckOutputLogError -OutputLog $ParcompPSOut
            if ($CheckOutputFlag) {
                $TestOps = WBase-GetTestOps -TestOut $ParcompPSOut -keyWords "Mbps"
                if ([String]::IsNullOrEmpty($TestOps) -or ($TestOps -eq "inf")) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "get_ops"
                } else {
                    $ReturnValue.result = $true
                    $ReturnValue.error = "no_error"
                    $ReturnValue.testOps = $TestOps
                }
            } else {
                $ReturnValue.result = $false
                $ReturnValue.error = "parcomp_failed"
            }
        }

        if ($ReturnValue.result) {
            Win-DebugTimestamp -output (
                "{0}: The parcomp test ({1}) is passed" -f
                    $LogKeyWord,
                    $runParcompType
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: The parcomp test ({1}) is failed > {2}" -f
                    $LogKeyWord,
                    $runParcompType,
                    $ReturnValue.error
            )
        }
    } elseif ($runParcompType -eq "AsJob") {
        # After running this parcomp type, must be check:
        # -parcomp output file
        # -job status
        # -job output log
        if ($Remote) {
            $ParcompJob = Invoke-Command -Session $Session -ScriptBlock {
                Param($ParcompExe, $ParcompArges)
                &$ParcompExe $ParcompArges.split()
            } -ArgumentList $ParcompExe, $ParcompArges -AsJob
        } else {
            $ParcompJob = Invoke-Command -ScriptBlock {
                Param($ParcompExe, $ParcompArges)
                &$ParcompExe $ParcompArges.split()
            } -ArgumentList $ParcompExe, $ParcompArges -AsJob
        }

        $ReturnValue.job = $ParcompJob
    } elseif ($runParcompType -eq "Process") {
        # After running this parcomp type, must be check:
        # -parcomp output file
        # -process status
        # -process error log
        # -process output log
        if ($Remote) {
            $ParcompProcess = Invoke-Command -Session $Session -ScriptBlock {
                Param($ParcompExe, $ParcompArges, $TestParcompOutLog, $TestParcompErrorLog)
                $ParcompProcess = Start-Process -FilePath $ParcompExe `
                              -ArgumentList $ParcompArges `
                              -RedirectStandardOutput $TestParcompOutLog `
                              -RedirectStandardError $TestParcompErrorLog `
                              -NoNewWindow `
                              -PassThru
                return $ParcompProcess
            } -ArgumentList $ParcompExe, $ParcompArges, $TestParcompOutLog, $TestParcompErrorLog
        } else {
            $ParcompProcess = Invoke-Command -ScriptBlock {
                Param($ParcompExe, $ParcompArges, $TestParcompOutLog, $TestParcompErrorLog)
                $ParcompProcess = Start-Process -FilePath $ParcompExe `
                              -ArgumentList $ParcompArges `
                              -RedirectStandardOutput $TestParcompOutLog `
                              -RedirectStandardError $TestParcompErrorLog `
                              -NoNewWindow `
                              -PassThru
                return $ParcompProcess
            } -ArgumentList $ParcompExe, $ParcompArges, $TestParcompOutLog, $TestParcompErrorLog
        }

        $ReturnValue.process = $ParcompProcess
    }

    return $ReturnValue
}

# About cngtest tool
function WBase-GenerateCNGTestCase
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$ArrayProvider,

        [Parameter(Mandatory=$True)]
        [array]$ArrayAlgo,

        [Parameter(Mandatory=$True)]
        [array]$ArrayOperation,

        [Parameter(Mandatory=$True)]
        [array]$ArrayKeyLength,

        [Parameter(Mandatory=$True)]
        [array]$ArrayEcccurve,

        [Parameter(Mandatory=$True)]
        [array]$ArrayPadding,

        [Parameter(Mandatory=$True)]
        [array]$ArrayIteration,

        [Parameter(Mandatory=$True)]
        [array]$ArrayThread
    )

    # $ReturnValue += [hashtable] @{
    #     Provider = "qa"
    #     Algo = "rsa"
    #     Operation = "encrypt"
    #     KeyLength = 4096
    #     Padding = "pkcs1"
    #     Ecccurve = "nistP256"
    #     Iteration = 96
    #     Thread = 10000
    # }
    $ReturnValue = [System.Array] @()

    Foreach ($Iteration in $ArrayIteration) {
        Foreach ($Thread in $ArrayThread) {
            Foreach ($Provider in $ArrayProvider) {
                Foreach ($Algo in $ArrayAlgo) {
                    Foreach ($Operation in $ArrayOperation) {
                        if ($Algo -eq "rsa") {
                            if (($Operation -eq "encrypt") -or ($Operation -eq "decrypt")) {
                                Foreach ($KeyLength in $ArrayKeyLength) {
                                    Foreach ($Padding in $ArrayPadding) {
                                        $ReturnValue += [hashtable] @{
                                            Provider = $Provider
                                            Algo = $Algo
                                            Operation = $Operation
                                            KeyLength = $KeyLength
                                            Padding = $Padding
                                            Ecccurve = "nistP256"
                                            Iteration = $Iteration
                                            Thread = $Thread
                                        }
                                    }
                                }
                            } else {
                                continue
                            }
                        }

                        if ($Algo -eq "ecdsa") {
                            if (($Operation -eq "sign") -or ($Operation -eq "verify")) {
                                Foreach ($Ecccurve in $ArrayEcccurve) {
                                    if ($Ecccurve -eq "curve25519") {
                                        continue
                                    } else {
                                        $ReturnValue += [hashtable] @{
                                            Provider = $Provider
                                            Algo = $Algo
                                            Operation = $Operation
                                            KeyLength = "4096"
                                            Padding = "pkcs1"
                                            Ecccurve = $Ecccurve
                                            Iteration = $Iteration
                                            Thread = $Thread
                                        }
                                    }
                                }
                            } else {
                                continue
                            }
                        }

                        if ($Algo -eq "dsa") {
                            if (($Operation -eq "sign") -or ($Operation -eq "verify")) {
                                Foreach ($KeyLength in $ArrayKeyLength) {
                                    $ReturnValue += [hashtable] @{
                                        Provider = $Provider
                                        Algo = $Algo
                                        Operation = $Operation
                                        KeyLength = $KeyLength
                                        Padding = "pkcs1"
                                        Ecccurve = "nistP256"
                                        Iteration = $Iteration
                                        Thread = $Thread
                                    }
                                }
                            } else {
                                continue
                            }
                        }

                        if ($Algo -eq "ecdh") {
                            if (($Operation -eq "derivekey") -or ($Operation -eq "secretderive") -or ($Operation -eq "secretagreement")) {
                                Foreach ($Ecccurve in $ArrayEcccurve) {
                                    if (($Operation -ne "derivekey") -and ($Ecccurve -eq "curve25519")) {
                                        continue
                                    } else {
                                        $ReturnValue += [hashtable] @{
                                            Provider = $Provider
                                            Algo = $Algo
                                            Operation = $Operation
                                            KeyLength = "4096"
                                            Padding = "pkcs1"
                                            Ecccurve = $Ecccurve
                                            Iteration = $Iteration
                                            Thread = $Thread
                                        }
                                    }
                                }
                            }
                        }

                        if ($Algo -eq "dh") {
                            if (($Operation -eq "derivekey") -or ($Operation -eq "secretderive") -or ($Operation -eq "secretagreement")) {
                                Foreach ($KeyLength in $ArrayKeyLength) {
                                    $ReturnValue += [hashtable] @{
                                        Provider = $Provider
                                        Algo = $Algo
                                        Operation = $Operation
                                        KeyLength = $KeyLength
                                        Padding = "pkcs1"
                                        Ecccurve = "nistP256"
                                        Iteration = $Iteration
                                        Thread = $Thread
                                    }
                                }
                            } else {
                                continue
                            }
                        }
                    }
                }
            }
        }
    }

    return $ReturnValue
}

function WBase-CNGTest
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [Parameter(Mandatory=$True)]
        [string]$algo,

        [string]$operation = "encrypt",

        [string]$provider = "qa",

        [int]$keyLength = 2048,

        [string]$ecccurve = "nistP256",

        [string]$padding = "pkcs1",

        [string]$numThreads = 120,

        [string]$numIter = 100000,

        [string]$TestPath = $null,

        [object]$Session = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        process = $null
    }

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $CNGTestOpts.PathName
    }

    if ($Remote) {
        $PSSessionName = $Session.Name
        Invoke-Command -Session $Session -ScriptBlock {
            Param($TestPath)
            if (Test-Path -Path $TestPath) {
                Get-Item -Path $TestPath | Remove-Item -Recurse
            }
            New-Item -Path $TestPath -ItemType Directory
        } -ArgumentList $TestPath | out-null
    } else {
        if (Test-Path -Path $TestPath) {
            Get-Item -Path $TestPath | Remove-Item -Recurse
        }
        New-Item -Path $TestPath -ItemType Directory
    }

    $CNGTestExe = "{0}\\{1}" -f $CNGTestOpts.CNGTestPath, $CNGTestOpts.CNGTestExeName
    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog

    $CNGTestArges = "-provider={0} -numThreads={1} -numIter={2}" -f
        $provider,
        $numThreads,
        $numIter
    if ($algo -eq "rsa") {
        $CNGTestArges += " -algo={0} -keyLength={1}" -f $algo, $keyLength

        if ($padding) {
            $CNGTestArges += " -padding={0}" -f $padding
        }

        if ($operation -and (($operation -eq "encrypt") -or ($operation -eq "decrypt"))) {
            $CNGTestArges += " -{0}" -f $operation
        }
    } elseif ($algo -eq "ecdsa") {
        $CNGTestArges += " -algo={0} -ecccurve={1}" -f $algo, $ecccurve

        if ($operation -and (($operation -eq "sign") -or ($operation -eq "verify"))) {
            $CNGTestArges += " -{0}" -f $operation
        }
    } elseif ($algo -eq "dsa") {
        $CNGTestArges += " -algo={0} -keyLength={1}" -f $algo, $keyLength

        if ($operation -and (($operation -eq "sign") -or ($operation -eq "verify"))) {
            $CNGTestArges += " -{0}" -f $operation
        }
    } elseif ($algo -eq "ecdh") {
        $CNGTestArges += " -algo={0} -ecccurve={1}" -f $algo, $ecccurve

        if ($operation -and (($operation -eq "derivekey") -or ($operation -eq "secretderive") -or ($operation -eq "secretagreement"))) {
            $CNGTestArges += " -{0}" -f $operation
        }
    } elseif ($algo -eq "dh") {
        $CNGTestArges += " -algo={0} -keyLength={1}" -f $algo, $keyLength

        if ($operation -and (($operation -eq "derivekey") -or ($operation -eq "secretderive") -or ($operation -eq "secretagreement"))) {
            $CNGTestArges += " -{0}" -f $operation
        }
    } else {
        Win-DebugTimestamp -output ("{0}: The CNG test is not support provider > {0}" -f $PSSessionName, $algo)
        $ReturnValue.result = $false
        $ReturnValue.error = ("provider_{0}" -f $algo)
        return $ReturnValue
    }

    Win-DebugTimestamp -output (
        "{0}: CNG test > {1} {2}" -f $PSSessionName, $CNGTestExe, $CNGTestArges
    )
    # After running CNG test, must be check:
    # -CNGTest output file
    # -process status
    # -process error log
    # -process output log
    if ($Remote) {
        $CNGTestPSOut = Invoke-Command -Session $Session -ScriptBlock {
            Param($CNGTestExe, $CNGTestArges, $CNGTestOutLog, $CNGTestErrorLog)
            $CNGTestProcess = Start-Process -FilePath $CNGTestExe `
                -ArgumentList $CNGTestArges `
                -RedirectStandardOutput $CNGTestOutLog `
                -RedirectStandardError $CNGTestErrorLog `
                -NoNewWindow `
                -PassThru
            return $CNGTestProcess
        } -ArgumentList $CNGTestExe, $CNGTestArges, $CNGTestOutLog, $CNGTestErrorLog
    } else {
        $CNGTestPSOut = Invoke-Command -ScriptBlock {
            Param($CNGTestExe, $CNGTestArges, $CNGTestOutLog, $CNGTestErrorLog)
            $CNGTestProcess = Start-Process -FilePath $CNGTestExe `
                -ArgumentList $CNGTestArges `
                -RedirectStandardOutput $CNGTestOutLog `
                -RedirectStandardError $CNGTestErrorLog `
                -NoNewWindow `
                -PassThru
            return $CNGTestProcess
        } -ArgumentList $CNGTestExe, $CNGTestArges, $CNGTestOutLog, $CNGTestErrorLog
    }

    $ReturnValue.process = $CNGTestPSOut

    return $ReturnValue
}


Export-ModuleMember -Variable *-*
Export-ModuleMember -Function *-*
