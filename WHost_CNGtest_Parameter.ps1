Param(
    [Parameter(Mandatory=$True)]
    [string]$BertaResultPath,

    [bool]$RunOnLocal = $false,

    [bool]$UQMode = $false,

    [bool]$TestMode = $true,

    [bool]$VerifierMode = $true,

    [bool]$DebugMode = $false,

    [string]$runTestCase = $null,

    [string]$DriverPath = "C:\\cy-work\\qat_driver\\",

    [string]$ResultFile = "result.log"
)

$TestSuitePath = Split-Path -Path $PSCommandPath
Set-Variable -Name "QATTESTPATH" -Value $TestSuitePath -Scope global

Import-Module "$QATTESTPATH\\lib\\WinHost.psm1" -Force -DisableNameChecking
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

        $BertaConfig["UQ_mode"] = ($out.config.UQ_mode -eq "true") ? $true : $false
        $BertaConfig["test_mode"] = ($out.config.test_mode -eq "true") ? $true : $false
        $BertaConfig["driver_verifier"] = ($out.config.driver_verifier -eq "true") ? $true : $false
        $BertaConfig["DebugMode"] = $false

        $job2 = $out.jobs | Where-Object {$_.job_id -eq 2}
        $LocalBuildPath = $job2.bld_path
    }

    $LocationInfo.HVMode = $false
    $LocationInfo.IsWin = $true
    $LocationInfo.VM.IsWin = $null
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $LocalBuildPath

    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
                           -QatDriverFullPath $PFVFDriverPath `
                           -BertaConfig $BertaConfig | out-null

    [System.Array]$CompareTypes = ("true", "false")

    # Special: For All
    if ([String]::IsNullOrEmpty($runTestCase)) {
        [System.Array]$CNGTestProvider = ("qa")
    } else {
        $AnalyzeResult = WBase-AnalyzeTestCaseName -TestCaseName $runTestCase
        [System.Array]$CNGTestProvider = $AnalyzeResult.CNGTest.Provider
        [System.Array]$CNGTestAlgo = $AnalyzeResult.CNGTest.Algo
        [System.Array]$CNGTestEcccurve = $AnalyzeResult.CNGTest.Ecccurve
        [System.Array]$CNGTestKeyLength = $AnalyzeResult.CNGTest.KeyLength
        [System.Array]$CNGTestPadding = $AnalyzeResult.CNGTest.Padding
        [System.Array]$CNGTestOperation = $AnalyzeResult.CNGTest.Operation
        [System.Array]$CNGTestIteration = $AnalyzeResult.CNGTest.Iteration
        [System.Array]$CNGTestThread = $AnalyzeResult.CNGTest.Thread
    }

    $CNGTestPathName = "CNGTest"

    # Special: For QAT17
    if ($LocationInfo.QatType -eq "QAT17") {
        if ($LocationInfo.UQMode) {
            throw ("QAT17: On the Host, not support UQ Mode.")
        }
    }

    # Special: For QAT18
    if ($LocationInfo.QatType -eq "QAT18") {
        if ($LocationInfo.UQMode) {
            throw ("QAT18: On the Host, not support UQ Mode.")
        }
    }

    # Special: For QAT20
    if ($LocationInfo.QatType -eq "QAT20") {
        if ([String]::IsNullOrEmpty($runTestCase)) {
            [System.Array]$CNGTestAlgo = ("rsa", "ecdsa", "ecdh")
        }
    }

    # CNGTest: Generate test case list based on config
    $TestCaseList = WBase-GenerateCNGTestCase `
        -ArrayProvider $CNGTestProvider `
        -ArrayAlgo $CNGTestAlgo `
        -ArrayOperation $CNGTestOperation `
        -ArrayKeyLength $CNGTestKeyLength `
        -ArrayEcccurve $CNGTestEcccurve `
        -ArrayPadding $CNGTestPadding `
        -ArrayIteration $CNGTestIteration `
        -ArrayThread $CNGTestThread

    Foreach ($CompareType in $CompareTypes) {
        if ($CompareType -eq "true") {
            $CompareFlag = $true
            Win-DebugTimestamp -output (
                "Create compare file: {0}" -f $CompareFile
            )
        }

        if ($CompareType -eq "false") {
            $CompareFlag = $false
            Win-DebugTimestamp -output ("Initialize test environment....")
            WinHost-ENVInit | out-null

            Win-DebugTimestamp -output ("Start to run test case....")
        }

        $UQString = ($LocationInfo.UQMode) ? "UQ" : "NUQ"
        $testNameHeader = "Regression_Host_{0}_{1}_Perf_Parameter" -f
            $LocationInfo.QatType,
            $UQString

        Foreach ($TestCase in $TestCaseList) {
            $testName = "{0}_{1}_{2}_Thread{3}_Iteration{4}_{5}" -f
                $testNameHeader,
                $TestCase.Provider,
                $TestCase.Algo,
                $TestCase.Thread,
                $TestCase.Iteration,
                $TestCase.Operation

            if (($TestCase.Algo -eq "ecdsa") -or ($TestCase.Algo -eq "ecdh")) {
                $testName = "{0}_{1}" -f $testName, $TestCase.Ecccurve
            } else {
                $testName = "{0}_KeyLength{1}" -f $testName, $TestCase.KeyLength
            }

            if ($TestCase.Algo -eq "rsa") {
                $testName = "{0}_{1}" -f $testName, $TestCase.Padding
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

                $CNGTestResult = WinHost-CNGTestBase `
                    -algo $TestCase.Algo `
                    -operation $TestCase.Operation `
                    -provider $TestCase.Provider `
                    -keyLength $TestCase.KeyLength `
                    -padding $TestCase.Padding `
                    -ecccurve $TestCase.Ecccurve `
                    -numThreads $TestCase.Thread `
                    -numIter $TestCase.Iteration `
                    -TestPathName $CNGTestPathName `
                    -BertaResultPath $BertaResultPath

                if ($CNGTestResult.result) {
                    $CNGTestResult.result = $TestResultToBerta.Pass
                } else {
                    $CNGTestResult.result = $TestResultToBerta.Fail
                }

                $TestCaseResultsList = [hashtable] @{
                    tc = $testName
                    s = $CNGTestResult.result
                    e = $CNGTestResult.error
                }

                WBase-WriteTestResult -TestResult $TestCaseResultsList
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
