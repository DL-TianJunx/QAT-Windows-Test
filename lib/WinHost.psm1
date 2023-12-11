
function WinHost-ENVInit
{
    # Check QAT devices
    $CheckFlag = WBase-CheckQatDevice `
        -Remote $false `
        -CheckStatus "OK"
    if (-not $CheckFlag.result) {
        throw ("Host: The number of QAT devices is incorrect")
    }

    # Check driver verifier
    $CheckFlag = UT-CheckDriverVerifier `
        -CheckFlag $LocationInfo.VerifierMode `
        -Remote $false
    if (-not $CheckFlag) {
        throw ("Host: Driver verifier is incorrect")
    }

    # Check test mode
    $CheckFlag = UT-CheckTestMode `
        -CheckFlag $LocationInfo.TestMode `
        -Remote $false
    if (-not $CheckFlag) {
        throw ("Host: Test mode is incorrect")
    }

    # Check debug mode
    $CheckFlag = UT-CheckDebugMode `
        -CheckFlag $LocationInfo.DebugMode `
        -Remote $false
    if (-not $CheckFlag) {
        throw ("Host: Debug mode is incorrect")
    }

    # Check UQ mode
    $CheckFlag = UT-CheckUQMode `
        -CheckFlag $LocationInfo.UQMode `
        -Remote $false
    if (-not $CheckFlag) {
        throw ("Host: UQ mode is incorrect")
    }
}

# About base test
function WinHostErrorHandle
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$BertaResultPath,

        [Parameter(Mandatory=$True)]
        [string]$TestError,

        [Parameter(Mandatory=$True)]
        [string]$ParameterFileName,

        [bool]$Transfer = $false
    )

    # Stop trace and transfer tracelog file
    UT-TraceLogStop -Remote $false | out-null
    if ($Transfer) {UT-TraceLogTransfer -Remote $false | out-null}

    # Handle:
    #    -process_timeout
    #    -BSOD_error
    #    -Copy tracelog file to 'BertaResultPath'
    if ($TestError -eq "process_timeout") {
        $ProcessNameArray = [System.Array] @("parcomp", "cngtest")
        $ProcessNameArray | ForEach-Object {
            $ProcessError = $null
            $ProcessStatus = Get-Process -Name $_ `
                                         -ErrorAction SilentlyContinue `
                                         -ErrorVariable ProcessError

            if ([String]::IsNullOrEmpty($ProcessError)) {
                Stop-Process -Name $_ -Force
            }
        }
    }

    if ($TestError -eq "BSOD_error") {
        if (Test-Path -Path $SiteKeep.DumpFile) {
            $Local2HostDumpFile = "{0}\\Dump_{1}_host.DMP" -f
                $BertaResultPath,
                $ParameterFileName
            Copy-Item -Path $SiteKeep.DumpFile `
                      -Destination $Local2HostDumpFile `
                      -Force `
                      -Confirm:$false | out-null

            Get-Item -Path $Local2HostDumpFile | Remove-Item -Recurse
        }
    }

    Win-DebugTimestamp -output ("Host: Copy tracelog etl files to 'BertaResultPath'")
    $LocationInfo.PDBNameArray.Host | ForEach-Object {
        $BertaEtlFile = "{0}\\Tracelog_{1}_{2}_host.etl" -f $BertaResultPath, $_, $ParameterFileName
        $LocalEtlFile = $TraceLogOpts.EtlFullPath[$_]
        if (Test-Path -Path $LocalEtlFile) {
            Copy-Item -Path $LocalEtlFile -Destination $BertaEtlFile -Force -Confirm:$false | out-null
            Get-Item -Path $LocalEtlFile | Remove-Item -Recurse
        }
    }
}

# Test: installer check
function WinHost-InstallerCheckBase
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
    Foreach ($CheckType in $CheckTypes) {
        Win-DebugTimestamp -output ("Host: After QAT driver installed, double check > {0}" -f $CheckType)
        $CheckTestResult = WBase-CheckQatDriver -Side "host" `
                                                -Type $CheckType `
                                                -Operation $true `
                                                -QatDriverServices $QatDriverServices `
                                                -QatDriverLibs $QatDriverLibs

        if ($CheckType -eq "service") {
            $ReturnValue.install.service.result = $CheckTestResult
            if (!$CheckTestResult) {
                $ReturnValue.install.service.error = "install_service_fail"
            }
        } elseif ($CheckType -eq "device") {
            $ReturnValue.install.device.result = $CheckTestResult
            if (!$CheckTestResult) {
                $ReturnValue.install.device.error = "install_device_fail"
            }
        } elseif ($CheckType -eq "library") {
            $ReturnValue.install.library.result = $CheckTestResult
            if (!$CheckTestResult) {
                $ReturnValue.install.library.error = "install_library_fail"
            }
        }
    }

    # Run parcomp test after QAT Windows driver installed
    if ($parcompFlag) {
        Win-DebugTimestamp -output ("After QAT driver installed, double check > run parcomp test")
        $parcompTestResult = WinHost-ParcompBase -deCompressFlag $false `
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
        $CNGTestTestResult = WinHost-CNGTestBase -algo "rsa" -BertaResultPath $BertaResultPath

        Win-DebugTimestamp -output ("Running cngtest is completed > {0}" -f $CNGTestTestResult.result)

        $ReturnValue.cngtest.result = $CNGTestTestResult.result
        $ReturnValue.cngtest.error = $CNGTestTestResult.error
    }

    # Uninstall QAT Windows driver
    Win-DebugTimestamp -output ("Host: uninstall Qat driver")
    WBase-InstallAndUninstallQatDriver -SetupExePath $LocationInfo.PF.DriverExe `
                                       -Operation $false `
                                       -Remote $false

    WBase-CheckDriverInstalled -Remote $false | out-null

    # Run QAT Windows driver check: uninstall
    Foreach ($CheckType in $CheckTypes) {
        Win-DebugTimestamp -output ("Host: After QAT driver uninstalled, double check > {0}" -f $CheckType)
        $CheckTestResult = WBase-CheckQatDriver -Side "host" `
                                                -Type $CheckType `
                                                -Operation $false `
                                                -QatDriverServices $QatDriverServices `
                                                -QatDriverLibs $QatDriverLibs

        if ($CheckType -eq "service") {
            $ReturnValue.uninstall.service.result = $CheckTestResult
            if (!$CheckTestResult) {
                $ReturnValue.uninstall.service.error = "uninstall_service_fail"
            }
        } elseif ($CheckType -eq "device") {
            $ReturnValue.uninstall.device.result = $CheckTestResult
            if (!$CheckTestResult) {
                $ReturnValue.uninstall.device.error = "uninstall_device_fail"
            }
        } elseif ($CheckType -eq "library") {
            $ReturnValue.uninstall.library.result = $CheckTestResult
            if (!$CheckTestResult) {
                $ReturnValue.uninstall.library.error = "uninstall_library_fail"
            }
        }
    }

    return $ReturnValue
}

# Test: installer disable and enable
function WinHost-InstallerCheckDisable
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

    # Run simple parcomp test to check qat driver work well
    if ($parcompFlag) {
        Win-DebugTimestamp -output ("After QAT driver installed, double check > run parcomp test")
        $parcompTestResult = WinHost-ParcompBase -deCompressFlag $false `
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
        $CNGTestTestResult = WinHost-CNGTestBase -algo "rsa"

        Win-DebugTimestamp -output ("Running cngtest is completed > {0}" -f $CNGTestTestResult.result)

        $ReturnValue.cngtest.result = $CNGTestTestResult.result
        $ReturnValue.cngtest.error = $CNGTestTestResult.error
    }

    # Run disable and enable qat device on VMs
    Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on VMs")
    $disableStatus = WBase-EnableAndDisableQatDevice -Remote $false

    Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
    if (!$disableStatus) {
        $ReturnValue.disable.result = $disableStatus
        $ReturnValue.disable.error = "disable_failed"
    }

    # Run simple parcomp test again to check qat driver work well
    if ($parcompFlag) {
        Win-DebugTimestamp -output ("After QAT driver disable and enable, double check > run parcomp test")
        $parcompTestResult = WinHost-ParcompBase -deCompressFlag $false `
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
        $CNGTestTestResult = WinHost-CNGTestBase -algo "rsa"

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
function WinHost-ParcompBase
{
    Param(
        [bool]$deCompressFlag = $false,

        [string]$CompressProvider = "qat",

        [string]$deCompressProvider = "qat",

        [string]$QatCompressionType = "dynamic",

        [int]$Level = 1,

        [int]$Chunk = 64,

        [string]$TestFilefullPath = $null,

        [string]$TestPath = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200,

        [string]$TestType = "Parameter"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    $TestSourceFile = "{0}\\{1}{2}.txt" -f
        $STVWinPath,
        $TestFileType,
        $TestFileSize
    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.PathName
    }

    # Run tracelog
    UT-TraceLogStart -Remote $false | out-null

    # Run parcomp exe
    if ($deCompressFlag) {
        Win-DebugTimestamp -output (
            "Host: Start to {0} test (decompress) with {1} provider!" -f
                $TestType,
                $deCompressProvider
        )
    } else {
        Win-DebugTimestamp -output (
            "Host: Start to {0} test (compress) test with {1} provider!" -f
                $TestType,
                $CompressProvider
        )
    }

    $ParcompTestResult = WBase-Parcomp -Side "host" `
                                       -deCompressFlag $deCompressFlag `
                                       -CompressProvider $CompressProvider `
                                       -deCompressProvider $deCompressProvider `
                                       -QatCompressionType $QatCompressionType `
                                       -Level $Level `
                                       -Chunk $Chunk `
                                       -TestPath $TestPath `
                                       -TestFilefullPath $TestFilefullPath `
                                       -TestFileType $TestFileType `
                                       -TestFileSize $TestFileSize

    # Get parcomp test result
    $ReturnValue.result = $ParcompTestResult.result
    $ReturnValue.error = $ParcompTestResult.error

    # Double check the output file
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "Host: Double check the output file of {0} test" -f $TestType
        )

        $CheckMD5Result = WBase-CheckOutputFile `
            -Remote $false `
            -deCompressFlag $deCompressFlag `
            -CompressProvider $CompressProvider `
            -deCompressProvider $deCompressProvider `
            -QatCompressionType $QatCompressionType `
            -Level $Level `
            -Chunk $Chunk `
            -TestPath $TestPath `
            -TestFileType $TestFileType `
            -TestFileSize $TestFileSize

        if ($ReturnValue.result -and !$CheckMD5Result.result) {
            $ReturnValue.result = $CheckMD5Result.result
            $ReturnValue.error = $CheckMD5Result.error
        }
    } else {
        Win-DebugTimestamp -output ("Host: Skip checking the output file of {0} test, because Error > {1}" -f $TestType, $ReturnValue.error)
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

            $ParameterFileName = "{0}_{1}_chunk{2}" -f
                $CompressionType,
                $CompressionProvider,
                $Chunk

            if (!$deCompressFlag) {
                $ParameterFileName = "{0}_level{1}" -f
                    $ParameterFileName,
                    $Level
            }

            if ($deCompressProvider -eq "qat") {
                $ParameterFileName = "{0}_{1}" -f
                    $ParameterFileName,
                    $QatCompressionType
            }
        } elseif ($TestType -eq "Compat") {
            $ParameterFileName = "Compress_{0}_deCompress_{1}" -f
                $CompressProvider,
                $deCompressProvider
        }

        WinHostErrorHandle `
            -TestError $ReturnValue.error `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName | out-null
    }

    return $ReturnValue
}

# Test: performance test of parcomp
function WinHost-ParcompPerformance
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

        [string]$TestPath = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestFileType = "high",

        [int]$TestFileSize = 200,

        [string]$TestType = "Performance"
    )

    # Test type 'Performance' and 'BanchMark' base on Host
    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testOps = 0
        TestFileType = $TestFileType
    }

    $ParcompType = "Performance"
    $runParcompType = "Process"

    $TestSourceFile = "{0}\\{1}{2}.txt" -f $STVWinPath, $TestFileType, $TestFileSize
    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.PathName
    }

    $TestParcompInFile = "{0}\\{1}" -f $TestPath, $ParcompOpts.InputFileName
    $TestParcompOutFile = "{0}\\{1}" -f $TestPath, $ParcompOpts.OutputFileName
    $TestParcompOutLog = "{0}\\{1}" -f $TestPath, $ParcompOpts.OutputLog
    $TestParcompErrorLog = "{0}\\{1}" -f $TestPath, $ParcompOpts.ErrorLog

    # Stop trace log tool
    UT-TraceLogStop -Remote $false | out-null

    # Run parcomp exe
    if ($deCompressFlag) {
        Win-DebugTimestamp -output ("Host: Start to {0} test (decompress) with {1} provider!" -f $TestType, $deCompressProvider)
    } else {
        Win-DebugTimestamp -output ("Host: Start to {0} test (compress) with {1} provider!" -f $TestType, $CompressProvider)
    }

    $ParcompTestResult = WBase-Parcomp -Side "host" `
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
                                       -TestFilefullPath $TestFilefullPath `
                                       -TestFileType $TestFileType `
                                       -TestFileSize $TestFileSize

    # Check parcomp test process number
    $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "parcomp"
    if ($ReturnValue.result) {
        $ReturnValue.result = $CheckProcessNumberFlag.result
        $ReturnValue.error = $CheckProcessNumberFlag.error
    }

    # Wait parcomp test process to complete
    $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "parcomp" -Remote $false
    if ($ReturnValue.result) {
        $ReturnValue.result = $WaitProcessFlag.result
        $ReturnValue.error = $WaitProcessFlag.error
    }

    # Check parcomp test result
    $CheckOutput = WBase-CheckOutputLog `
        -TestOutputLog $TestParcompOutLog `
        -TestErrorLog $TestParcompErrorLog `
        -Remote $false `
        -keyWords "Mbps"

    $ReturnValue.result = $CheckOutput.result
    $ReturnValue.error = $CheckOutput.error
    $ReturnValue.testOps = $CheckOutput.testOps

    if ($TestType -eq "Parameter") {
        # Double check the output files
        if ($ReturnValue.result) {
            Win-DebugTimestamp -output ("Host: Double check the output file of performance test ({0})" -f $TestType)
            $CheckMD5Result = WBase-CheckOutputFile `
                -Remote $false `
                -deCompressFlag $deCompressFlag `
                -CompressProvider $CompressProvider `
                -deCompressProvider $deCompressProvider `
                -QatCompressionType $QatCompressionType `
                -Level $Level `
                -Chunk $Chunk `
                -blockSize $blockSize `
                -TestPath $TestPath `
                -TestFileType $TestFileType `
                -TestFileSize $TestFileSize

            if ($ReturnValue.result -and !$CheckMD5Result.result) {
                $ReturnValue.result = $CheckMD5Result.result
                $ReturnValue.error = $CheckMD5Result.error
            }
        } else {
            Win-DebugTimestamp -output ("Host: Skip checking the output files of performance test ({0}), because Error > {1}" -f $TestType, $ReturnValue.error)
        }
    }

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

        WinHostErrorHandle `
            -TestError $ReturnValue.error `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName | out-null
    }

    return $ReturnValue
}

# Test: SWFallback test of parcomp
function WinHost-ParcompSWfallback
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

    $SWFallbackCheck = [hashtable] @{
        Hardware2Software = "Hardware compression failed, attempting software fallback"
        HandleQATError = "handleQatError() failed"
        HandleSWFallbackError = "handleSWFallback() failed"
    }

    $ParcompType = "Fallback"
    $runParcompType = "Process"
    $CompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.CompressPathName
    $deCompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.deCompressPathName

    # Run tracelog
    UT-TraceLogStart -Remote $false | out-null

    # Run parcomp exe
    Win-DebugTimestamp -output ("Host: Start to {0} test ({1}) with {2} provider!" -f $TestType,
                                                                                      $CompressType,
                                                                                      $deCompressProvider)

    $ProcessCount = 0
    if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
        $ProcessCount += 1
        $deCompressTestResult = WBase-Parcomp -Side "host" `
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
                                              -TestFilefullPath $TestFilefullPath `
                                              -TestFileType $TestFileType `
                                              -TestFileSize $TestFileSize

        Start-Sleep -Seconds 5
    }

    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
        $ProcessCount += 1
        $CompressTestResult = WBase-Parcomp -Side "host" `
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
                                            -TestFilefullPath $TestFilefullPath `
                                            -TestFileType $TestFileType `
                                            -TestFileSize $TestFileSize

        Start-Sleep -Seconds 5
    }

    # Check parcomp test process number
    $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "parcomp" -ProcessNumber $ProcessCount
    if ($ReturnValue.result) {
        $ReturnValue.result = $CheckProcessNumberFlag.result
        $ReturnValue.error = $CheckProcessNumberFlag.error
    }

    # Operation: heartbeat, disable, upgrade
    if ($ReturnValue.result) {
        if ($TestType -eq "heartbeat") {
            Win-DebugTimestamp -output ("Run 'heartbeat' operation on local host")
            $heartbeatStatus = WBase-HeartbeatQatDevice -LogPath $BertaResultPath

            Win-DebugTimestamp -output ("The heartbeat operation > {0}" -f $heartbeatStatus)
            if (-not $heartbeatStatus) {
                $ReturnValue.result = $heartbeatStatus
                $ReturnValue.error = "heartbeat_failed"
            }
        } elseif ($TestType -eq "disable") {
            Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on local host")
            $disableStatus = WBase-EnableAndDisableQatDevice -Remote $false

            Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
            if (-not $disableStatus) {
                $ReturnValue.result = $disableStatus
                $ReturnValue.error = "disable_failed"
            }
        } elseif ($TestType -eq "upgrade") {
            Win-DebugTimestamp -output ("Run 'upgrade' operation on local host")
            $upgradeStatus = WBase-UpgradeQatDevice

            Win-DebugTimestamp -output ("The upgrade operation > {0}" -f $upgradeStatus)
            if (-not $upgradeStatus) {
                $ReturnValue.result = $upgradeStatus
                $ReturnValue.error = "upgrade_failed"
            }
        } else {
            Win-DebugTimestamp -output ("The fallback test does not support test type > {0}" -f $TestType)
            $ReturnValue.result = $false
            $ReturnValue.error = ("test_type_{0}" -f $TestType)
        }
    } else {
        Win-DebugTimestamp -output ("Host: Skip {0} operation, because Error > {1}" -f $TestType, $ReturnValue.error)
    }

    # Wait parcomp test process to complete
    $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "parcomp" -Remote $false
    if ($ReturnValue.result) {
        $ReturnValue.result = $WaitProcessFlag.result
        $ReturnValue.error = $WaitProcessFlag.error
    }

    # Check parcomp test result
    $CompressTestOutLogPath = "{0}\\{1}" -f $CompressTestPath, $ParcompOpts.OutputLog
    $CompressTestErrorLogPath = "{0}\\{1}" -f $CompressTestPath, $ParcompOpts.ErrorLog
    $deCompressTestOutLogPath = "{0}\\{1}" -f $deCompressTestPath, $ParcompOpts.OutputLog
    $deCompressTestErrorLogPath = "{0}\\{1}" -f $deCompressTestPath, $ParcompOpts.ErrorLog

    if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
        $CheckOutput = WBase-CheckOutputLog `
            -TestOutputLog $CompressTestOutLogPath `
            -TestErrorLog $CompressTestErrorLogPath `
            -Remote $false `
            -keyWords "Mbps"

        if ($ReturnValue.result) {
            $ReturnValue.result = $CheckOutput.result
            $ReturnValue.error = $CheckOutput.error
        }
    }

    if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
        $CheckOutput = WBase-CheckOutputLog `
            -TestOutputLog $deCompressTestOutLogPath `
            -TestErrorLog $deCompressTestErrorLogPath `
            -Remote $false `
            -keyWords "Mbps"

        if ($ReturnValue.result) {
            $ReturnValue.result = $CheckOutput.result
            $ReturnValue.error = $CheckOutput.error
        }
    }

    # Double check the output files
    if ($ReturnValue.result) {
        if (($CompressType -eq "Compress") -or ($CompressType -eq "All")) {
            Win-DebugTimestamp -output ("Host: Double check the output file of fallback test (compress)")
            $CheckMD5Result = WBase-CheckOutputFile `
                -Remote $false `
                -deCompressFlag $false `
                -CompressProvider $CompressProvider `
                -deCompressProvider $deCompressProvider `
                -QatCompressionType $QatCompressionType `
                -Level $Level `
                -Chunk $Chunk `
                -blockSize $blockSize `
                -TestPath $CompressTestPath `
                -TestFileType $TestFileType `
                -TestFileSize $TestFileSize

            if ($ReturnValue.result -and !$CheckMD5Result.result) {
                $ReturnValue.result = $CheckMD5Result.result
                $ReturnValue.error = $CheckMD5Result.error
            }
        }

        if (($CompressType -eq "deCompress") -or ($CompressType -eq "All")) {
            Win-DebugTimestamp -output ("Host: Double check the output file of fallback test (decompress)")
            $CheckMD5Result = WBase-CheckOutputFile `
                -Remote $false `
                -deCompressFlag $true `
                -CompressProvider $CompressProvider `
                -deCompressProvider $deCompressProvider `
                -QatCompressionType $QatCompressionType `
                -Level $Level `
                -Chunk $Chunk `
                -blockSize $blockSize `
                -TestPath $deCompressTestPath `
                -TestFileType $TestFileType `
                -TestFileSize $TestFileSize

            if ($ReturnValue.result -and !$CheckMD5Result.result) {
                $ReturnValue.result = $CheckMD5Result.result
                $ReturnValue.error = $CheckMD5Result.error
            }
        }
    } else {
        Win-DebugTimestamp -output ("Host: Skip checking the output files of fallback test, because Error > {0}" -f $ReturnValue.error)
    }

    # Run parcomp test after fallback test
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output ("Double check: Run parcomp test after fallback test")
        $parcompTestResult = WinHost-ParcompBase -deCompressFlag $false `
                                                 -CompressProvider $CompressProvider `
                                                 -deCompressProvider $CompressProvider `
                                                 -QatCompressionType $QatCompressionType `
                                                 -BertaResultPath $BertaResultPath

        Win-DebugTimestamp -output ("Double check: The parcomp test is completed > {0}" -f $parcompTestResult.result)
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

        WinHostErrorHandle `
            -TestError $ReturnValue.error `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName | out-null
    }

    return $ReturnValue
}

# Test: base test of CNGTest
function WinHost-CNGTestBase
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

        [string]$TestPath = $null,

        [string]$BertaResultPath = "C:\\temp"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $CNGTestOpts.PathName
    }

    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog

    # Run tracelog
    UT-TraceLogStart -Remote $false | out-null

    # Run CNGTest exe
    Win-DebugTimestamp -output ("Host: Start to {0} test ({1}) with {2} provider!" -f $algo,
                                                                                      $operation,
                                                                                      $provider)

    $CNGTestResult = WBase-CNGTest -Side "host" `
                                   -algo $algo `
                                   -operation $operation `
                                   -provider $provider `
                                   -keyLength $keyLength `
                                   -ecccurve $ecccurve `
                                   -padding $padding `
                                   -numThreads $numThreads `
                                   -numIter $numIter `
                                   -TestPath $TestPath

    # Check CNGTest test process number
    $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "cngtest"
    if ($ReturnValue.result) {
        $ReturnValue.result = $CheckProcessNumberFlag.result
        $ReturnValue.error = $CheckProcessNumberFlag.error
    }

    # Wait CNGTest test process to complete
    $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "cngtest" -Remote $false
    if ($ReturnValue.result) {
        $ReturnValue.result = $WaitProcessFlag.result
        $ReturnValue.error = $WaitProcessFlag.error
    }

    # Check CNGTest test result
    $CheckOutput = WBase-CheckOutputLog `
        -TestOutputLog $CNGTestOutLog `
        -TestErrorLog $CNGTestErrorLog `
        -Remote $false `
        -keyWords "Ops/s"

    if ($ReturnValue.result) {
        $ReturnValue.result = $CheckOutput.result
        $ReturnValue.error = $CheckOutput.error
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

        WinHostErrorHandle `
            -TestError $ReturnValue.error `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName | out-null
    }

    return $ReturnValue
}

# Test: performance test of CNGTest
function WinHost-CNGTestPerformance
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

        [string]$TestPath = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestType = "Performance"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        testOps = 0
        error = "no_error"
    }

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $CNGTestOpts.PathName
    }

    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog

    # Stop trace log tool
    UT-TraceLogStop -Remote $false | out-null

    # Run CNGTest exe
    Win-DebugTimestamp -output ("Host: Start to {0} test ({1}) with {2} provider!" -f $algo,
                                                                                      $operation,
                                                                                      $provider)

    $CNGTestResult = WBase-CNGTest -Side "host" `
                                   -algo $algo `
                                   -operation $operation `
                                   -provider $provider `
                                   -keyLength $keyLength `
                                   -ecccurve $ecccurve `
                                   -padding $padding `
                                   -numThreads $numThreads `
                                   -numIter $numIter `
                                   -TestPath $TestPath

    # Check CNGTest test process number
    $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "cngtest"
    if ($ReturnValue.result) {
        $ReturnValue.result = $CheckProcessNumberFlag.result
        $ReturnValue.error = $CheckProcessNumberFlag.error
    }

    # Wait CNGTest test process to complete
    $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "cngtest" -Remote $false
    if ($ReturnValue.result) {
        $ReturnValue.result = $WaitProcessFlag.result
        $ReturnValue.error = $WaitProcessFlag.error
    }

    # Check CNGTest test result
    $CheckOutput = WBase-CheckOutputLog `
        -TestOutputLog $CNGTestOutLog `
        -TestErrorLog $CNGTestErrorLog `
        -Remote $false `
        -keyWords "Ops/s"

    $ReturnValue.result = $CheckOutput.result
    $ReturnValue.error = $CheckOutput.error
    $ReturnValue.testOps = $CheckOutput.testOps

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

        WinHostErrorHandle `
            -TestError $ReturnValue.error `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName | out-null
    }

    return $ReturnValue
}

# Test: SWFallback test of CNGTest
function WinHost-CNGTestSWfallback
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

        [string]$TestPath = $null,

        [string]$BertaResultPath = "C:\\temp",

        [string]$TestType = "heartbeat"
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
    }

    if ([String]::IsNullOrEmpty($TestPath)) {
        $TestPath = "{0}\\{1}" -f $STVWinPath, $CNGTestOpts.PathName
    }

    $CNGTestOutLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.OutputLog
    $CNGTestErrorLog = "{0}\\{1}" -f $TestPath, $CNGTestOpts.ErrorLog

    # Run tracelog
    UT-TraceLogStart -Remote $false | out-null

    # Run CNGTest exe
    Win-DebugTimestamp -output ("Host: Start to {0} test ({1}) with {2} operation!" -f $TestType,
                                                                                       $algo,
                                                                                       $operation)

    $CNGTestResult = WBase-CNGTest -Side "host" `
                                   -algo $algo `
                                   -operation $operation `
                                   -provider $provider `
                                   -keyLength $keyLength `
                                   -ecccurve $ecccurve `
                                   -padding $padding `
                                   -numThreads $numThreads `
                                   -numIter $numIter `
                                   -TestPath $TestPath

    Start-Sleep -Seconds 10

    # Check CNGTest test process number
    $CheckProcessNumberFlag = WBase-CheckProcessNumber -ProcessName "cngtest"
    if ($ReturnValue.result) {
        $ReturnValue.result = $CheckProcessNumberFlag.result
        $ReturnValue.error = $CheckProcessNumberFlag.error
    }

    # Operation: heartbeat, disable, upgrade
    if ($ReturnValue.result) {
        if ($TestType -eq "heartbeat") {
            Win-DebugTimestamp -output ("Run 'heartbeat' operation on local host")
            $heartbeatStatus = WBase-HeartbeatQatDevice -LogPath $BertaResultPath

            Win-DebugTimestamp -output ("The heartbeat operation > {0}" -f $heartbeatStatus)
            if (-not $heartbeatStatus) {
                $ReturnValue.result = $heartbeatStatus
                $ReturnValue.error = "heartbeat_failed"
            }
        } elseif ($TestType -eq "disable") {
            Win-DebugTimestamp -output ("Run 'disable' and 'enable' operation on local host")
            $disableStatus = WBase-EnableAndDisableQatDevice -Remote $false

            Win-DebugTimestamp -output ("The disable and enable operation > {0}" -f $disableStatus)
            if (-not $disableStatus) {
                $ReturnValue.result = $disableStatus
                $ReturnValue.error = "disable_failed"
            }
        } elseif ($TestType -eq "upgrade") {
            Win-DebugTimestamp -output ("Run 'upgrade' operation on local host")
            $upgradeStatus = WBase-UpgradeQatDevice

            Win-DebugTimestamp -output ("The upgrade operation > {0}" -f $upgradeStatus)
            if (-not $upgradeStatus) {
                $ReturnValue.result = $upgradeStatus
                $ReturnValue.error = "upgrade_failed"
            }
        } else {
            Win-DebugTimestamp -output ("The fallback test does not support test type > {0}" -f $TestType)
            $ReturnValue.result = $false
            $ReturnValue.error = ("test_type_{0}" -f $TestType)
        }
    } else {
        Win-DebugTimestamp -output ("Host: Skip {0} operation, because Error > {1}" -f $TestType, $ReturnValue.error)
    }

    # Wait CNGTest test process to complete
    $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "cngtest" -Remote $false
    if ($ReturnValue.result) {
        $ReturnValue.result = $WaitProcessFlag.result
        $ReturnValue.error = $WaitProcessFlag.error
    }

    # Check CNGTest test result
    $CheckOutput = WBase-CheckOutputLog `
        -TestOutputLog $CNGTestOutLog `
        -TestErrorLog $CNGTestErrorLog `
        -Remote $false `
        -keyWords "Ops/s"

    if ($ReturnValue.result) {
        $ReturnValue.result = $CheckOutput.result
        $ReturnValue.error = $CheckOutput.error
    }

    # Run CNGTest after fallback test
    if ($ReturnValue.result) {
        Win-DebugTimestamp -output ("Double check: Run CNGTest after fallback test")

        $CNGTestTestResult = WinHost-CNGTestBase -algo $algo

        Win-DebugTimestamp -output ("Running cngtest is completed > {0}" -f $CNGTestTestResult.result)

        if ($ReturnValue.result) {
            $ReturnValue.result = $CNGTestTestResult.result
            $ReturnValue.error = $CNGTestTestResult.error
        }
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
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $keyLength
        }

        if ($algo -eq "rsa") {
            $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $padding
        }

        $ParameterFileName = "{0}_{1}" -f $ParameterFileName, $TestType

        WinHostErrorHandle `
            -TestError $ReturnValue.error `
            -BertaResultPath $BertaResultPath `
            -ParameterFileName $ParameterFileName | out-null
    }

    return $ReturnValue
}

# Test: stress test of parcomp and CNGTest
function WinHost-Stress
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

    $ParcompType = "Performance"
    $runParcompType = "Process"
    $CompressType = "All"
    $CompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.CompressPathName
    $deCompressTestPath = "{0}\\{1}" -f $STVWinPath, $ParcompOpts.deCompressPathName
    $CNGTestPath = "{0}\\{1}" -f $STVWinPath, $CNGTestOpts.PathName

    # Run test
    if ($RunParcomp) {
        Win-DebugTimestamp -output ("Host: Start to compress test")
        $CompressTestResult = WBase-Parcomp -Side "host" `
                                            -deCompressFlag $false `
                                            -ParcompType $ParcompType `
                                            -runParcompType $runParcompType `
                                            -TestPath $CompressTestPath

        Start-Sleep -Seconds 5

        Win-DebugTimestamp -output ("Host: Start to decompress test")
        $deCompressTestResult = WBase-Parcomp -Side "host" `
                                              -deCompressFlag $true `
                                              -ParcompType $ParcompType `
                                              -runParcompType $runParcompType `
                                              -TestPath $deCompressTestPath

        Start-Sleep -Seconds 5
    }

    if ($RunCNGtest) {
        Win-DebugTimestamp -output ("Host: Start to cng test")
        $CNGTestResult = WBase-CNGTest -Side "host" -algo "rsa"
    }

    # Get test result
    if ($RunParcomp) {
        $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "parcomp" -Remote $false
        if ($ReturnValue.result) {
            $ReturnValue.result = $WaitProcessFlag.result
            $ReturnValue.error = $WaitProcessFlag.error
        }

        $CompressTestOutLogPath = "{0}\\{1}" -f $CompressTestPath, $ParcompOpts.OutputLog
        $CompressTestErrorLogPath = "{0}\\{1}" -f $CompressTestPath, $ParcompOpts.ErrorLog
        $deCompressTestOutLogPath = "{0}\\{1}" -f $deCompressTestPath, $ParcompOpts.OutputLog
        $deCompressTestErrorLogPath = "{0}\\{1}" -f $deCompressTestPath, $ParcompOpts.ErrorLog

        $CheckOutput = WBase-CheckOutputLog `
            -TestOutputLog $CompressTestOutLogPath `
            -TestErrorLog $CompressTestErrorLogPath `
            -Remote $false `
            -keyWords "Mbps"

        if ($ReturnValue.result) {
            $ReturnValue.result = $CheckOutput.result
            $ReturnValue.error = $CheckOutput.error
        }

        $CheckOutput = WBase-CheckOutputLog `
            -TestOutputLog $deCompressTestOutLogPath `
            -TestErrorLog $deCompressTestErrorLogPath `
            -Remote $false `
            -keyWords "Mbps"

        if ($ReturnValue.result) {
            $ReturnValue.result = $CheckOutput.result
            $ReturnValue.error = $CheckOutput.error
        }

        if ($ReturnValue.result) {
            Win-DebugTimestamp -output ("Host: The parcomp test ({0}) of stress is passed" -f $CompressType)
        }
    }

    if ($RunCNGtest) {
        $WaitProcessFlag = WBase-WaitProcessToCompletedByName -ProcessName "cngtest" -Remote $false
        if ($ReturnValue.result) {
            $ReturnValue.result = $WaitProcessFlag.result
            $ReturnValue.error = $WaitProcessFlag.error
        }

        $CNGTestOutLog = "{0}\\{1}" -f $CNGTestPath, $CNGTestOpts.OutputLog
        $CNGTestErrorLog = "{0}\\{1}" -f $CNGTestPath, $CNGTestOpts.ErrorLog

        $CheckOutput = WBase-CheckOutputLog `
            -TestOutputLog $CNGTestOutLog `
            -TestErrorLog $CNGTestErrorLog `
            -Remote $false `
            -keyWords "Ops/s"

        if ($ReturnValue.result) {
            $ReturnValue.result = $CheckOutput.result
            $ReturnValue.error = $CheckOutput.error
        }

        if ($ReturnValue.result) {
            Win-DebugTimestamp -output ("Host: The CNGtest of stress is passed")
        }
    }

    return $ReturnValue
}


Export-ModuleMember -Function *-*
