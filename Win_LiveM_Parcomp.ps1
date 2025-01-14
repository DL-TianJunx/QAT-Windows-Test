Param(
    [Parameter(Mandatory=$True)]
    [string]$BertaResultPath,

    [bool]$RunOnLocal = $false,

    [bool]$UseS2D = $false,

    [array]$VMVFOSConfigs = $null,

    [bool]$UQMode = $false,

    [bool]$TestMode = $true,

    [bool]$VerifierMode = $true,

    [bool]$DebugMode = $false,

    [bool]$FailToStop = $false,

    [string]$runTestCase = $null,

    [string]$TargetServer = $null,

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
        $BertaConfig["TargetServer"] = $TargetServer
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
        $BertaConfig["TargetServer"] = $out.config.TargetServer

        $job2 = $out.jobs | Where-Object {$_.job_id -eq 2}
        $LocalBuildPath = $job2.bld_path
    }

    if ([String]::IsNullOrEmpty($BertaConfig["TargetServer"])) {
        throw ("The TargetServer is null, please double check.")
    }

    $LocationInfo.HVMode = $true
    $LocationInfo.IsWin = $true
    $LocationInfo.VM.IsWin = $true
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $LocalBuildPath

    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
                           -QatDriverFullPath $PFVFDriverPath `
                           -BertaConfig $BertaConfig | out-null

    $DomainRemoteInfo = Domain-RemoteInfoInit `
        -BertaConfig $BertaConfig `
        -BuildPath $LocalBuildPath `
        -UseS2D $UseS2D

    if ([String]::IsNullOrEmpty($VMVFOSConfigs)) {
        [System.Array]$VMVFOSConfigs = HV-GenerateVMVFConfig `
            -ConfigType "LiveM" `
            -RemoteInfo $DomainRemoteInfo
    }

    [System.Array]$CompareTypes = ("true", "false")

    # Special: For All
    if ([String]::IsNullOrEmpty($runTestCase)) {
        [System.Array]$ParcompProvider = ("qatgzipext", "qatlz4")
        [System.Array]$ParcompCompressionType = ("dynamic")
        [System.Array]$ParcompCompressionLevel = (1, 4)
        [System.Array]$ParcompChunk = (32, 64)
        [System.Array]$ParcompBlock = (4096)
        [System.Array]$ParcompThread = (2)
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
        [System.Array]$AllTestType.Operation = $AnalyzeResult.Operation
        [System.Array]$VMVFOSConfigs = $AnalyzeResult.VMVFOS
    }

    # Special: For QAT17
    if ($LocationInfo.QatType -eq "QAT17") {
        if ($LocationInfo.UQMode) {
            throw ("QAT17: On the HVMode, not support UQ Mode.")
        }
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

            $testNameHeader = "LiveM_{0}_{1}_{2}" -f
                $LocationInfo.QatType,
                $UQString,
                $VMVFOSConfig

            if (-not $CompareFlag) {
                Win-DebugTimestamp -output ("Initialize test environment....")
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


                $DomainRemoteInfo = Domain-RemoteVMVFConfigInit `
                    -RemoteInfo $DomainRemoteInfo `
                    -VMVFOSConfig $VMVFOSConfig `
                    -UseS2D $UseS2D

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
                    $DomainRemoteInfo.TestCaseName = $testName

                    $LiveMTestResult = Domain-LiveMParcomp `
                        -RemoteInfo $DomainRemoteInfo `
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
                        -UseS2D $UseS2D

                    if (-not ([string]($LiveMTestResult.gettype()) -eq "hashtable")) {
                        $LiveMTestResult = $LiveMTestResult[-1]
                    }

                    if ($LiveMTestResult.result) {
                        $LiveMTestResult.result = $TestResultToBerta.Pass
                    } else {
                        $LiveMTestResult.result = $TestResultToBerta.Fail

                        if ($FailToStop) {
                            throw ("If test caes is failed, then stop testing.")
                        }
                    }

                    $TestCaseResultsList = [hashtable] @{
                        tc = $testName
                        s = $LiveMTestResult.result
                        e = $LiveMTestResult.error
                    }

                    WBase-WriteTestResult -TestResult $TestCaseResultsList
                }
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
