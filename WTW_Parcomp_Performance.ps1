Param(
    [Parameter(Mandatory=$True)]
    [string]$BertaResultPath,

    [bool]$RunOnLocal = $false,

    [bool]$InitVM = $true,

    [array]$VMVFOSConfigs = $null,

    [bool]$UQMode = $false,

    [bool]$TestMode = $true,

    [bool]$VerifierMode = $false,

    [bool]$DebugMode = $false,

    [bool]$FailToStop = $false,

    [string]$runTestCase = $null,

    [string]$DriverPath = "C:\\cy-work\\qat_driver\\",

    [string]$ResultFile = "result.log"
)

$TestSuitePath = Split-Path -Path $PSCommandPath
Set-Variable -Name "QATTESTPATH" -Value $TestSuitePath -Scope global

$ModuleStatus = Get-Module -Name "WinBase"
if ([String]::IsNullOrEmpty($ModuleStatus)) {
    Import-Module "$QATTESTPATH\\lib\\WinBase.psm1" -Force -DisableNameChecking
}

WBase-ReturnFilesInit `
    -BertaResultPath $BertaResultPath `
    -ResultFile $ResultFile | out-null
$TestSuiteName = (Split-Path -Path $PSCommandPath -Leaf).Split(".")[0]
$CompareFile = "{0}\\CompareFile_{1}.log" -f
    $BertaResultPath,
    $TestSuiteName

try {
    $BertaConfig = [hashtable] @{}
    if ($RunOnLocal) {
        $BertaConfig["UQ_mode"] = $UQMode
        $BertaConfig["test_mode"] = $TestMode
        $BertaConfig["driver_verifier"] = $VerifierMode
        $BertaConfig["DebugMode"] = $DebugMode
        $LocationInfo.WriteLogToConsole = $true
        $LocalBuildPath = $DriverPath
    } else {
        $FilePath = Join-Path -Path $BertaResultPath -ChildPath "task.json"
        $out = Get-Content -LiteralPath $FilePath | ConvertFrom-Json -AsHashtable

        if ($out.config.UQ_mode -eq "true") {
            $BertaConfig["UQ_mode"] = $true
        } else {
            $BertaConfig["UQ_mode"] = $false
        }

        if ($out.config.test_mode -eq "true") {
            $BertaConfig["test_mode"] = $true
        } else {
            $BertaConfig["test_mode"] = $false
        }

        if ($out.config.driver_verifier -eq "true") {
            $BertaConfig["driver_verifier"] = $true
        } else {
            $BertaConfig["driver_verifier"] = $false
        }

        $BertaConfig["DebugMode"] = $false

        $job2 = $out.jobs | Where-Object {$_.job_id -eq 2}
        $LocalBuildPath = $job2.bld_path
    }

    $LocationInfo.HVMode = $true
    $LocationInfo.IsWin = $true
    $LocationInfo.VM.IsWin = $true
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $LocalBuildPath

    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
                           -QatDriverFullPath $PFVFDriverPath `
                           -BertaConfig $BertaConfig | out-null

    [System.Array]$CompareTypes = ("true", "false")

    # Special: For All
    if ([String]::IsNullOrEmpty($runTestCase)) {
        [System.Array]$ParcompProvider = ("qat")
        [System.Array]$ParcompCompressType = ("Compress", "deCompress")
        [System.Array]$ParcompCompressionType = ("dynamic")
        [System.Array]$ParcompCompressionLevel = (1)
        [System.Array]$ParcompChunk = (8, 64, 128)
        [System.Array]$ParcompBlock = (4096)
        [System.Array]$ParcompThread = (16)
        [System.Array]$ParcompIteration = (200)
    } else {
        $AnalyzeResult = WBase-AnalyzeTestCaseName -TestCaseName $runTestCase
        [System.Array]$ParcompProvider = $AnalyzeResult.Parcomp.Provider
        [System.Array]$ParcompChunk = $AnalyzeResult.Parcomp.Chunk
        [System.Array]$ParcompBlock = $AnalyzeResult.Parcomp.Block
        [System.Array]$ParcompCompressType = $AnalyzeResult.Parcomp.CompressType
        [System.Array]$ParcompCompressionLevel = $AnalyzeResult.Parcomp.Level
        [System.Array]$ParcompCompressionType = $AnalyzeResult.Parcomp.CompressionType
        [System.Array]$ParcompIteration = $AnalyzeResult.Parcomp.Iteration
        [System.Array]$ParcompThread = $AnalyzeResult.Parcomp.Thread
        [System.Array]$TestFileNameArray.Type = $AnalyzeResult.Parcomp.TestFileType
        [System.Array]$TestFileNameArray.Size = $AnalyzeResult.Parcomp.TestFileSize
        [System.Array]$VMVFOSConfigs = $AnalyzeResult.VMVFOS
    }

    $TestType = "Performance"
    $RunIterations = 1

    if ([String]::IsNullOrEmpty($VMVFOSConfigs)) {
        [System.Array]$VMVFOSConfigs = HV-GenerateVMVFConfig -ConfigType $TestType
    }

    # Special: For QAT17
    if ($LocationInfo.QatType -eq "QAT17") {
        if ($LocationInfo.UQMode) {
            throw ("QAT17: On the HVMode, not support UQ Mode.")
        }

        [System.Array]$TestFileNameArray.Type = ("calgary")
    }

    # Special: For QAT18
    if ($LocationInfo.QatType -eq "QAT18") {
        if ($LocationInfo.UQMode) {
            throw ("QAT18: On the HVMode, not support UQ Mode.")
        }
    }

    # Special: For QAT20
    if ($LocationInfo.QatType -eq "QAT20") {
        if ($LocationInfo.UQMode) {
            throw ("QAT20: On the HVMode, not support UQ Mode.")
        }
    }

    # Parcomp: Generate test case list based on config
    $TestCaseList = WBase-GenerateParcompTestCase `
        -ArrayProvider $ParcompProvider `
        -ArrayChunk $ParcompChunk `
        -ArrayBlock $ParcompBlock `
        -ArrayCompressType $ParcompCompressType `
        -ArrayCompressionType $ParcompCompressionType `
        -ArrayCompressionLevel $ParcompCompressionLevel `
        -ArrayIteration $ParcompIteration `
        -ArrayThread $ParcompThread `
        -ArrayTestFileType $TestFileNameArray.Type`
        -ArrayTestFileSize $TestFileNameArray.Size

    Foreach ($CompareType in $CompareTypes) {
        if ($CompareType -eq "true") {
            $CompareFlag = $true
            Win-DebugTimestamp -output (
                "Create compare file: {0}" -f $CompareFile
            )
        }

        if ($CompareType -eq "false") {
            $CompareFlag = $false
        }

        Foreach ($VMVFOSConfig in $VMVFOSConfigs) {
            if ($LocationInfo.UQMode) {
                $UQString = "UQ"
            } else {
                $UQString = "NUQ"
            }

            $testNameHeader = "Regression_WTW_{0}_{1}_{2}_{3}" -f
                $LocationInfo.QatType,
                $UQString,
                $VMVFOSConfig,
                $TestType
            $BanchMarkFile = "{0}\\banchmark\\WTW_{1}_{2}_{3}_parcomp_banchmark.log" -f
                $QATTESTPATH,
                $LocationInfo.QatType,
                $UQString,
                $VMVFOSConfig

            if (-not $CompareFlag) {
                Win-DebugTimestamp -output ("Initialize test environment....")
                WTW-ENVInit -VMVFOSConfig $VMVFOSConfig -InitVM $InitVM | out-null

                Win-DebugTimestamp -output ("Start to run test case....")
                Win-DebugTimestamp -output ("-------------------------------------------------------------------------------------------------")
            }

            Foreach ($TestCase in $TestCaseList) {
                # deCompress: qatgzip not support -k -t -Q
                if ($TestCase.Provider -eq "qatgzip") {
                    if (($TestCase.CompressType -eq "deCompress") -or
                        ($TestCase.CompressType -eq "All")) {
                        continue
                    }
                }

                $testName = "{0}_{1}_{2}_Thread{3}_Iteration{4}_Block{5}_Chunk{6}_{7}{8}" -f
                    $testNameHeader,
                    $TestCase.Provider,
                    $TestCase.CompressType,
                    $TestCase.Thread,
                    $TestCase.Iteration,
                    $TestCase.Block,
                    $TestCase.Chunk,
                    $TestCase.TestFileType,
                    $TestCase.TestFileSize

                if ($TestCase.CompressType -eq "Compress") {
                    $testName = "{0}_Level{1}" -f
                        $testName,
                        $TestCase.CompressionLevel
                }

                if ($TestCase.Provider -eq "qat") {
                    $testName = "{0}_{1}" -f
                        $testName,
                        $TestCase.CompressionType
                }

                if ($CompareFlag) {
                    $TestCaseResultsList = [hashtable] @{
                        tc = $testName
                        s = $TestResultToBerta.NotRun
                        e = "no_error"
                    }

                    WBase-WriteTestResult `
                        -TestResult $TestCaseResultsList `
                        -ResultFile $CompareFile
                } else {
                    Win-DebugTimestamp -output ("Start to run test case > {0}" -f $testName)
                    $LocationInfo.TestCaseName = $testName

                    $totalOps = 0
                    $totalResult = $true
                    $totalError = "no_error"
                    ForEach ($RunIteration in (1..$RunIterations)) {
                        Win-DebugTimestamp -output (
                            "--------- > {0} time" -f $RunIteration
                        )

                        $PerformanceTestResult = WTW-Parcomp `
                            -CompressType $TestCase.CompressType `
                            -CompressProvider $TestCase.Provider `
                            -deCompressProvider $TestCase.Provider `
                            -QatCompressionType $TestCase.CompressionType `
                            -Level $TestCase.CompressionLevel `
                            -Chunk $TestCase.Chunk `
                            -blockSize $TestCase.Block `
                            -numThreads $TestCase.Thread `
                            -numIterations $TestCase.Iteration `
                            -TestFileType $TestCase.TestFileType `
                            -TestFileSize $TestCase.TestFileSize `
                            -TestType $TestType

                        Win-DebugTimestamp -output (
                            "Get {0} value on {1} time > {2}" -f
                                $TestType,
                                $RunIteration,
                                $PerformanceTestResult.testOps
                        )

                        $totalOps += $PerformanceTestResult.testOps

                        if (-not $PerformanceTestResult.result) {
                            $totalResult = $PerformanceTestResult.result
                            $totalError = $PerformanceTestResult.error
                        }
                    }

                    $testOps = [int]($totalOps / $RunIterations)
                    $CheckOpsResult = WBase-CheckTestOps `
                        -BanchMarkFile $BanchMarkFile `
                        -testOps $testOps `
                        -testName $testName

                    if ($totalResult -and !$CheckOpsResult.result) {
                        $totalResult = $CheckOpsResult.result
                        $totalError = "performance_degradation"
                    }

                    if ($totalResult) {
                        $totalResult = $TestResultToBerta.Pass
                    } else {
                        $totalResult = $TestResultToBerta.Fail

                        if ($FailToStop) {
                            throw ("If test caes is failed, then stop testing.")
                        }
                    }

                    $TestCaseResultsList = [hashtable] @{
                        tc = $testName
                        s = $totalResult
                        e = $totalError
                        testOps = $testOps
                        banckmarkOps = $CheckOpsResult.banckmarkOps
                    }

                    WBase-WriteTestResult -TestResult $TestCaseResultsList
                }
            }

            if (-not $CompareFlag) {
                Win-DebugTimestamp -output ("Clear test environment....")
                WTW-ENVClear -InitVM $InitVM | out-null
            }
        }

        if ($CompareFlag) {
            Win-DebugTimestamp -output (
                "Complete compare file: {0}" -f $CompareFile
            )
        }
    }
} catch {
    Win-DebugTimestamp -output $_
} finally {
    WBase-CompareTestResult -CompareFile $CompareFile
    Win-DebugTimestamp -output ("Ending $($MyInvocation.MyCommand)")
}
