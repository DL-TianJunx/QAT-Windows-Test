Param(
    [Parameter(Mandatory=$True)]
    [string]$BertaResultPath,

    [bool]$RunOnLocal = $false,

    [bool]$InitVM = $true,

    [array]$VMVFOSConfigs = $null,

    [bool]$UQMode = $false,

    [bool]$TestMode = $true,

    [bool]$VerifierMode = $true,

    [bool]$DebugMode = $false,

    [bool]$FailToStop = $false,

    [string]$DriverPath = "C:\\cy-work\\qat_driver\\",

    [string]$ResultFile = "result.log"
)

$TestSuitePath = Split-Path -Path $PSCommandPath
Set-Variable -Name "QATTESTPATH" -Value $TestSuitePath -Scope global

Import-Module "$QATTESTPATH\\lib\\WinHost.psm1" -Force -DisableNameChecking
Import-Module "$QATTESTPATH\\lib\\Win2Win.psm1" -Force -DisableNameChecking
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

        $BertaConfig["UQ_mode"] = $out.config.UQ_mode
        $BertaConfig["test_mode"] = ($out.config.test_mode -eq "true") ? $true : $false
        $BertaConfig["driver_verifier"] = ($out.config.driver_verifier -eq "true") ? $true : $false
        $BertaConfig["DebugMode"] = $false

        $job2 = $out.jobs | Where-Object {$_.job_id -eq 2}
        $LocalBuildPath = $job2.bld_path
    }

    $LocationInfo.HVMode = $true
    $LocationInfo.IsWin = $true
    $LocationInfo.VM.IsWin = $true
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $LocalBuildPath

    # Init QAT type
    WBase-HostDeviceInit | out-null

    # Init Smoke test type
    [System.Array]$CompareTypes = ("true", "false")
    [System.Array]$SmokeTestModeTypes = ("HostUQ", "HostNUQ", "HVMode")
    [System.Array]$SmokeTestTestTypes = ("Base", "Performance", "Fallback", "Installer")
    $SmokeTestTypesList = [hashtable] @{
        HostUQ = [hashtable] @{
            Flag = $false
            Base = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
            }
            Performance = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
            }
            Fallback = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                    Operation = [System.Array] @("heartbeat")
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                    Operation = [System.Array] @("heartbeat")
                }
            }
            Installer = [hashtable] @{
                Flag = $true
                CNGTest = $true
                Parcomp = $true
            }
        }
        HostNUQ = [hashtable] @{
            Flag = $false
            Base = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
            }
            Performance = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
            }
            Fallback = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                    Operation = [System.Array] @("heartbeat", "disable")
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                    Operation = [System.Array] @("heartbeat", "disable")
                }
            }
            Installer = [hashtable] @{
                Flag = $true
                CNGTest = $true
                Parcomp = $true
            }
        }
        HVMode = [hashtable] @{
            Flag = $false
            Base = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
            }
            Performance = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                }
            }
            Fallback = [hashtable] @{
                Flag = $true
                CNGTest = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                    Operation = [System.Array] @("heartbeat", "disable")
                }
                Parcomp = [hashtable] @{
                    Flag = $true
                    TestList = [System.Array] @()
                    Operation = [System.Array] @("heartbeat", "disable")
                }
            }
            Installer = [hashtable] @{
                Flag = $true
                CNGTest = $true
                Parcomp = $true
            }
        }
    }

    if ($BertaConfig["UQ_mode"] -eq "All") {
        $SmokeTestTypesList.HostUQ.Flag = $true
        $SmokeTestTypesList.HostNUQ.Flag = $true
        $SmokeTestTypesList.HVMode.Flag = $true
        $BertaConfig["UQ_mode"] = $false
        Win-DebugTimestamp -output ("Will run SmokeTest with UQ and NUQ mode....")
    } elseif ($BertaConfig["UQ_mode"] -eq "true") {
        $SmokeTestTypesList.HostUQ.Flag = $true
        $SmokeTestTypesList.HostNUQ.Flag = $false
        $SmokeTestTypesList.HVMode.Flag = $false
        $BertaConfig["UQ_mode"] = $true
        Win-DebugTimestamp -output ("Will run SmokeTest with UQ mode....")
    } else {
        $SmokeTestTypesList.HostUQ.Flag = $false
        $SmokeTestTypesList.HostNUQ.Flag = $true
        $SmokeTestTypesList.HVMode.Flag = $true
        $BertaConfig["UQ_mode"] = $false
        Win-DebugTimestamp -output ("Will run SmokeTest with NUQ mode....")
    }

    # Special: For All
    # If driver verifier is true, will not support performance test
    if ($BertaConfig["driver_verifier"]) {
        if ($SmokeTestTypesList.HostUQ.Flag) {
            if ($SmokeTestTypesList.HostUQ.Performance.Flag) {
                $SmokeTestTypesList.HostUQ.Performance.Flag = $false
            }
        }

        if ($SmokeTestTypesList.HostNUQ.Flag) {
            if ($SmokeTestTypesList.HostNUQ.Performance.Flag) {
                $SmokeTestTypesList.HostNUQ.Performance.Flag = $false
            }
        }

        if ($SmokeTestTypesList.HVMode.Flag) {
            if ($SmokeTestTypesList.HVMode.Performance.Flag) {
                $SmokeTestTypesList.HVMode.Performance.Flag = $false
            }
        }
    }

    Foreach ($SmokeTestModeType in $SmokeTestModeTypes) {
        Foreach ($SmokeTestTestType in $SmokeTestTestTypes) {
            if ($SmokeTestTypesList[$SmokeTestModeType].Flag) {
                if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Flag) {
                    # Installer: no testlist
                    if ($SmokeTestTestType -eq "Installer") {continue}

                    # Init CNGTest
                    [System.Array]$CNGTestProvider = ("qa")
                    [System.Array]$CNGTestAlgo = ("rsa", "ecdh", "ecdsa")
                    [System.Array]$CNGTestEcccurve = ("nistP256")
                    [System.Array]$CNGTestKeyLength = (2048)
                    [System.Array]$CNGTestPadding = ("oaep")
                    [System.Array]$CNGTestOperation = ("encrypt", "decrypt", "sign", "verify", "derivekey", "secretagreement")
                    [System.Array]$CNGTestIteration = (10)
                    [System.Array]$CNGTestThread = (1)

                    # Init parcomp
                    [System.Array]$ParcompProvider = ("qat", "qatgzip", "qatgzipext")
                    [System.Array]$ParcompChunk = (64)
                    [System.Array]$ParcompBlock = (4096)
                    [System.Array]$ParcompCompressType = ("Compress", "deCompress")
                    [System.Array]$ParcompCompressionLevel = (1)
                    [System.Array]$ParcompCompressionType = ("dynamic")
                    [System.Array]$ParcompIteration = (10)
                    [System.Array]$ParcompThread = (1)
                    [System.Array]$TestFileNameArray.Type = ("high", "calgary", "random")
                    [System.Array]$TestFileNameArray.Size = (200)

                    # Re-init for test type
                    if ($SmokeTestTestType -eq "Base") {
                        if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.Flag) {}

                        if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.Flag) {
                            if ($SmokeTestModeType -eq "HostUQ") {
                                $ParcompProvider += "qatlz4"
                            }
                        }
                    }

                    if ($SmokeTestTestType -eq "Performance") {
                        if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.Flag) {
                            [System.Array]$CNGTestIteration = (1000000)
                            [System.Array]$CNGTestThread = (96)
                        }

                        if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.Flag) {
                            if ($SmokeTestModeType -eq "HostUQ") {
                                $ParcompProvider += "qatlz4"
                            }

                            [System.Array]$ParcompIteration = (200)
                            [System.Array]$ParcompThread = (8)
                        }
                    }

                    if ($SmokeTestTestType -eq "Fallback") {
                        if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.Flag) {
                            [System.Array]$CNGTestIteration = (5000000)
                            [System.Array]$CNGTestThread = (96)
                        }

                        if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.Flag) {
                            [System.Array]$ParcompProvider = ("qatgzipext")
                            [System.Array]$TestFileNameArray.Type = ("calgary")
                            [System.Array]$TestFileNameArray.Size = (200)
                            [System.Array]$ParcompIteration = (200)
                            [System.Array]$ParcompThread = (8)
                        }
                    }

                    # Generate test case list
                    if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.Flag) {
                        $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.TestList = WBase-GenerateCNGTestCase `
                            -ArrayProvider $CNGTestProvider `
                            -ArrayAlgo $CNGTestAlgo `
                            -ArrayOperation $CNGTestOperation `
                            -ArrayKeyLength $CNGTestKeyLength `
                            -ArrayEcccurve $CNGTestEcccurve `
                            -ArrayPadding $CNGTestPadding `
                            -ArrayIteration $CNGTestIteration `
                            -ArrayThread $CNGTestThread
                    }

                    if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.Flag) {
                        $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.TestList = WBase-GenerateParcompTestCase `
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
                    }
                }
            }
        }
    }

    $CNGtestTestPathName = "CNGTest"
    $ParcompTestPathName = "ParcompTest"
    $VMVFOSConfig = "1vm_1vf_windows2022"

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

        Foreach ($SmokeTestModeType in $SmokeTestModeTypes) {
            if ($SmokeTestTypesList[$SmokeTestModeType].Flag) {
                Win-DebugTimestamp -output ("Smoke test mode type > {0}" -f $SmokeTestModeType)

                if ($SmokeTestModeType -eq "HostUQ") {
                    $BertaConfig["UQ_mode"] = $true
                    $LocationInfo.HVMode = $false
                    $LocationInfo.IsWin = $true
                    $LocationInfo.VM.IsWin = $null

                    # Special: For QAT17
                    if ($LocationInfo.QatType -eq "QAT17") {
                        throw (
                            "Host: {0} can not support UQ mode" -f $LocationInfo.QatType
                        )
                    }

                    # Special: For QAT18
                    if ($LocationInfo.QatType -eq "QAT18") {
                        throw (
                            "Host: {0} can not support UQ mode" -f $LocationInfo.QatType
                        )
                    }
                }

                if ($SmokeTestModeType -eq "HostNUQ") {
                    $BertaConfig["UQ_mode"] = $false
                    $LocationInfo.HVMode = $false
                    $LocationInfo.IsWin = $true
                    $LocationInfo.VM.IsWin = $null
                }

                if ($SmokeTestModeType -eq "HVMode") {
                    $BertaConfig["UQ_mode"] = $false
                    $LocationInfo.HVMode = $true
                    $LocationInfo.IsWin = $true
                    $LocationInfo.VM.IsWin = $true
                }

                if (-not $CompareFlag) {
                    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
                                           -QatDriverFullPath $PFVFDriverPath `
                                           -BertaConfig $BertaConfig | out-null

                    Win-DebugTimestamp -output ("{0}: Initialize test environment...." -f $SmokeTestModeType)
                    WinHost-ENVInit | out-null

                    if ($SmokeTestModeType -eq "HVMode") {
                        WTW-ENVInit -VMVFOSConfig $VMVFOSConfig -InitVM $InitVM | out-null
                    }

                    Win-DebugTimestamp -output ("{0}: Start to run test case...." -f $SmokeTestModeType)
                }

                Foreach ($SmokeTestTestType in $SmokeTestTestTypes) {
                    if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Flag) {
                        $testNameHeader = "SmokeTest_{0}_{1}_{2}" -f
                            $LocationInfo.QatType,
                            $SmokeTestModeType,
                            $SmokeTestTestType

                        if ($SmokeTestModeType -eq "HVMode") {
                            $testNameHeader = "{0}_{1}" -f
                                $testNameHeader,
                                $VMVFOSConfig
                        }

                        if (($SmokeTestTestType -eq "Base") -or
                            ($SmokeTestTestType -eq "Performance") -or
                            ($SmokeTestTestType -eq "Fallback")) {
                            if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.Flag) {
                                Foreach ($TestCase in $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.TestList) {
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
                                        if ($SmokeTestTestType -eq "Fallback") {
                                            Foreach ($TestType in $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.Operation) {
                                                $testNameTmp = "{0}_{1}" -f $testName, $TestType

                                                $TestCaseResultsList = [hashtable] @{
                                                    tc = $testNameTmp
                                                    s = $TestResultToBerta.NotRun
                                                    e = "no_error"
                                                }

                                                WBase-WriteTestResult `
                                                    -TestResult $TestCaseResultsList `
                                                    -ResultFile $CompareFile
                                            }
                                        } else {
                                            $TestCaseResultsList = [hashtable] @{
                                                tc = $testName
                                                s = $TestResultToBerta.NotRun
                                                e = "no_error"
                                            }

                                            WBase-WriteTestResult `
                                                -TestResult $TestCaseResultsList `
                                                -ResultFile $CompareFile
                                        }
                                    } else {
                                        if ($SmokeTestTestType -eq "Base") {
                                            if ($SmokeTestModeType -eq "HVMode") {
                                                $CNGTestResult = WTW-CNGTestBase `
                                                    -algo $TestCase.Algo `
                                                    -operation $TestCase.Operation `
                                                    -provider $TestCase.Provider `
                                                    -keyLength $TestCase.KeyLength `
                                                    -padding $TestCase.Padding `
                                                    -ecccurve $TestCase.Ecccurve `
                                                    -numThreads $TestCase.Thread `
                                                    -numIter $TestCase.Iteration `
                                                    -TestPathName $CNGtestTestPathName `
                                                    -BertaResultPath $BertaResultPath
                                            } else {
                                                $CNGTestResult = WinHost-CNGTestBase `
                                                    -algo $TestCase.Algo `
                                                    -operation $TestCase.Operation `
                                                    -provider $TestCase.Provider `
                                                    -keyLength $TestCase.KeyLength `
                                                    -padding $TestCase.Padding `
                                                    -ecccurve $TestCase.Ecccurve `
                                                    -numThreads $TestCase.Thread `
                                                    -numIter $TestCase.Iteration `
                                                    -TestPathName $CNGtestTestPathName `
                                                    -BertaResultPath $BertaResultPath
                                            }

                                            if ($CNGTestResult.result) {
                                                $CNGTestResult.result = $TestResultToBerta.Pass
                                            } else {
                                                $CNGTestResult.result = $TestResultToBerta.Fail

                                                if ($FailToStop) {
                                                    throw ("If test caes is failed, then stop testing.")
                                                }
                                            }

                                            $TestCaseResultsList = [hashtable] @{
                                                tc = $testName
                                                s = $CNGTestResult.result
                                                e = $CNGTestResult.error
                                            }

                                            WBase-WriteTestResult -TestResult $TestCaseResultsList
                                        }

                                        if ($SmokeTestTestType -eq "Performance") {
                                            $BanchMarkFile = "{0}\\banchmark\\SmokeTest_{1}_{2}_{3}_cngtest_banchmark.log" -f
                                                $QATTESTPATH,
                                                $LocationInfo.QatType,
                                                $SmokeTestModeType,
                                                $SmokeTestTestType

                                            if ($SmokeTestModeType -eq "HVMode") {
                                                $CNGTestResult = WTW-CNGTestPerformance `
                                                    -algo $TestCase.Algo `
                                                    -operation $TestCase.Operation `
                                                    -provider $TestCase.Provider `
                                                    -keyLength $TestCase.KeyLength `
                                                    -padding $TestCase.Padding `
                                                    -ecccurve $TestCase.Ecccurve `
                                                    -numThreads $TestCase.Thread `
                                                    -numIter $TestCase.Iteration `
                                                    -TestPathName $CNGtestTestPathName `
                                                    -BertaResultPath $BertaResultPath
                                            } else {
                                                $CNGTestResult = WinHost-CNGTestPerformance `
                                                    -algo $TestCase.Algo `
                                                    -operation $TestCase.Operation `
                                                    -provider $TestCase.Provider `
                                                    -keyLength $TestCase.KeyLength `
                                                    -padding $TestCase.Padding `
                                                    -ecccurve $TestCase.Ecccurve `
                                                    -numThreads $TestCase.Thread `
                                                    -numIter $TestCase.Iteration `
                                                    -TestPathName $CNGtestTestPathName `
                                                    -BertaResultPath $BertaResultPath
                                            }

                                            if ($CNGTestResult.result) {
                                                $CheckOpsResult = WBase-CheckTestOps `
                                                    -BanchMarkFile $BanchMarkFile `
                                                    -testOps $CNGTestResult.testOps `
                                                    -testName $testName

                                                if (!$CheckOpsResult.result) {
                                                    $CNGTestResult.result = $CheckOpsResult.result
                                                    $CNGTestResult.error = "performance_degradation"
                                                }
                                            }

                                            if ($CNGTestResult.result) {
                                                $CNGTestResult.result = $TestResultToBerta.Pass
                                            } else {
                                                $CNGTestResult.result = $TestResultToBerta.Fail

                                                if ($FailToStop) {
                                                    throw ("If test caes is failed, then stop testing.")
                                                }
                                            }

                                            $TestCaseResultsList = [hashtable] @{
                                                tc = $testName
                                                s = $CNGTestResult.result
                                                e = $CNGTestResult.error
                                            }

                                            WBase-WriteTestResult -TestResult $TestCaseResultsList
                                        }

                                        if ($SmokeTestTestType -eq "Fallback") {
                                            Foreach ($TestType in $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest.Operation) {
                                                $testNameTmp = "{0}_{1}" -f $testName, $TestType

                                                if ($SmokeTestModeType -eq "HVMode") {
                                                    $CNGTestResult = WTW-CNGTestSWfallback `
                                                        -algo $TestCase.Algo `
                                                        -operation $TestCase.Operation `
                                                        -provider $TestCase.Provider `
                                                        -keyLength $TestCase.KeyLength `
                                                        -padding $TestCase.Padding `
                                                        -ecccurve $TestCase.Ecccurve `
                                                        -numThreads $TestCase.Thread `
                                                        -numIter $TestCase.Iteration `
                                                        -TestPathName $CNGtestTestPathName `
                                                        -BertaResultPath $BertaResultPath `
                                                        -TestType $TestType
                                                } else {
                                                    $CNGTestResult = WinHost-CNGTestSWfallback `
                                                        -algo $TestCase.Algo `
                                                        -operation $TestCase.Operation `
                                                        -provider $TestCase.Provider `
                                                        -keyLength $TestCase.KeyLength `
                                                        -padding $TestCase.Padding `
                                                        -ecccurve $TestCase.Ecccurve `
                                                        -numThreads $TestCase.Thread `
                                                        -numIter $TestCase.Iteration `
                                                        -TestPathName $CNGtestTestPathName `
                                                        -BertaResultPath $BertaResultPath `
                                                        -TestType $TestType
                                                }

                                                if ($CNGTestResult.result) {
                                                    $CNGTestResult.result = $TestResultToBerta.Pass
                                                } else {
                                                    $CNGTestResult.result = $TestResultToBerta.Fail

                                                    if ($FailToStop) {
                                                        throw ("If test caes is failed, then stop testing.")
                                                    }
                                                }

                                                $TestCaseResultsList = [hashtable] @{
                                                    tc = $testNameTmp
                                                    s = $CNGTestResult.result
                                                    e = $CNGTestResult.error
                                                }

                                                WBase-WriteTestResult -TestResult $TestCaseResultsList
                                            }
                                        }
                                    }
                                }
                            }

                            if ($SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.Flag) {
                                Foreach ($TestCase in $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.TestList) {
                                    # deCompress: qatgzip not support -k -t -Q
                                    if (($SmokeTestTestType -eq "Performance") -or
                                        ($SmokeTestTestType -eq "Fallback")) {
                                        if ($TestCase.Provider -eq "qatgzip") {
                                            if (($TestCase.CompressType -eq "deCompress") -or
                                                ($TestCase.CompressType -eq "All")) {
                                                continue
                                            }
                                        }
                                    }

                                    if ($TestCase.CompressType -eq "Compress") {$deCompressFlag = $false}
                                    if ($TestCase.CompressType -eq "deCompress") {$deCompressFlag = $true}

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
                                        if ($SmokeTestTestType -eq "Fallback") {
                                            Foreach ($TestType in $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.Operation) {
                                                $testNameTmp = "{0}_{1}" -f $testName, $TestType

                                                $TestCaseResultsList = [hashtable] @{
                                                    tc = $testNameTmp
                                                    s = $TestResultToBerta.NotRun
                                                    e = "no_error"
                                                }

                                                WBase-WriteTestResult `
                                                    -TestResult $TestCaseResultsList `
                                                    -ResultFile $CompareFile
                                            }
                                        } else {
                                            $TestCaseResultsList = [hashtable] @{
                                                tc = $testName
                                                s = $TestResultToBerta.NotRun
                                                e = "no_error"
                                            }

                                            WBase-WriteTestResult `
                                                -TestResult $TestCaseResultsList `
                                                -ResultFile $CompareFile
                                        }
                                    } else {
                                        if ($SmokeTestTestType -eq "Base") {
                                            if ($SmokeTestModeType -eq "HVMode") {
                                                $ParcompTestResult = WTW-ParcompBase `
                                                    -deCompressFlag $deCompressFlag `
                                                    -CompressProvider $TestCase.Provider `
                                                    -deCompressProvider $TestCase.Provider `
                                                    -QatCompressionType $TestCase.CompressionType `
                                                    -Level $TestCase.CompressionLevel `
                                                    -Chunk $TestCase.Chunk `
                                                    -TestPathName $ParcompTestPathName `
                                                    -BertaResultPath $BertaResultPath `
                                                    -TestFileType $TestCase.TestFileType `
                                                    -TestFileSize $TestCase.TestFileSize
                                            } else {
                                                $ParcompTestResult = WinHost-ParcompBase `
                                                    -deCompressFlag $deCompressFlag `
                                                    -CompressProvider $TestCase.Provider `
                                                    -deCompressProvider $TestCase.Provider `
                                                    -QatCompressionType $TestCase.CompressionType `
                                                    -Level $TestCase.CompressionLevel `
                                                    -Chunk $TestCase.Chunk `
                                                    -TestPathName $ParcompTestPathName `
                                                    -BertaResultPath $BertaResultPath `
                                                    -TestFileType $TestCase.TestFileType `
                                                    -TestFileSize $TestCase.TestFileSize
                                            }

                                            if ($ParcompTestResult.result) {
                                                $ParcompTestResult.result = $TestResultToBerta.Pass
                                            } else {
                                                $ParcompTestResult.result = $TestResultToBerta.Fail

                                                if ($FailToStop) {
                                                    throw ("If test caes is failed, then stop testing.")
                                                }
                                            }

                                            $TestCaseResultsList = [hashtable] @{
                                                tc = $testName
                                                s = $ParcompTestResult.result
                                                e = $ParcompTestResult.error
                                            }

                                            WBase-WriteTestResult -TestResult $TestCaseResultsList
                                        }

                                        if ($SmokeTestTestType -eq "Performance") {
                                            $BanchMarkFile = "{0}\\banchmark\\SmokeTest_{1}_{2}_{3}_parcomp_banchmark.log" -f
                                                $QATTESTPATH,
                                                $LocationInfo.QatType,
                                                $SmokeTestModeType,
                                                $SmokeTestTestType

                                            if ($SmokeTestModeType -eq "HVMode") {
                                                $ParcompTestResult = WTW-ParcompPerformance `
                                                    -deCompressFlag $deCompressFlag `
                                                    -CompressProvider $TestCase.Provider `
                                                    -deCompressProvider $TestCase.Provider `
                                                    -QatCompressionType $TestCase.CompressionType `
                                                    -Level $TestCase.CompressionLevel `
                                                    -Chunk $TestCase.Chunk `
                                                    -numThreads $TestCase.Thread `
                                                    -numIterations $TestCase.Iteration `
                                                    -blockSize $TestCase.Block `
                                                    -TestPathName $ParcompTestPathName `
                                                    -BertaResultPath $BertaResultPath `
                                                    -TestFileType $TestCase.TestFileType `
                                                    -TestFileSize $TestCase.TestFileSize
                                            } else {
                                                $ParcompTestResult = WinHost-ParcompPerformance `
                                                    -deCompressFlag $deCompressFlag `
                                                    -CompressProvider $TestCase.Provider `
                                                    -deCompressProvider $TestCase.Provider `
                                                    -QatCompressionType $TestCase.CompressionType `
                                                    -Level $TestCase.CompressionLevel `
                                                    -Chunk $TestCase.Chunk `
                                                    -numThreads $TestCase.Thread `
                                                    -numIterations $TestCase.Iteration `
                                                    -blockSize $TestCase.Block `
                                                    -TestPathName $ParcompTestPathName `
                                                    -BertaResultPath $BertaResultPath `
                                                    -TestFileType $TestCase.TestFileType `
                                                    -TestFileSize $TestCase.TestFileSize
                                            }

                                            if ($ParcompTestResult.result) {
                                                $CheckOpsResult = WBase-CheckTestOps `
                                                    -BanchMarkFile $BanchMarkFile `
                                                    -testOps $ParcompTestResult.testOps `
                                                    -testName $testName

                                                if (!$CheckOpsResult.result) {
                                                    $ParcompTestResult.result = $CheckOpsResult.result
                                                    $ParcompTestResult.error = "performance_degradation"
                                                }
                                            }

                                            if ($ParcompTestResult.result) {
                                                $ParcompTestResult.result = $TestResultToBerta.Pass
                                            } else {
                                                $ParcompTestResult.result = $TestResultToBerta.Fail

                                                if ($FailToStop) {
                                                    throw ("If test caes is failed, then stop testing.")
                                                }
                                            }

                                            $TestCaseResultsList = [hashtable] @{
                                                tc = $testName
                                                s = $ParcompTestResult.result
                                                e = $ParcompTestResult.error
                                            }

                                            WBase-WriteTestResult -TestResult $TestCaseResultsList
                                        }

                                        if ($SmokeTestTestType -eq "Fallback") {
                                            Foreach ($TestType in $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp.Operation) {
                                                $testNameTmp = "{0}_{1}" -f $testName, $TestType

                                                if ($SmokeTestModeType -eq "HVMode") {
                                                    $ParcompTestResult = WTW-ParcompSWfallback `
                                                        -CompressType $TestCase.CompressType `
                                                        -CompressProvider $TestCase.Provider `
                                                        -deCompressProvider $TestCase.Provider `
                                                        -QatCompressionType $TestCase.CompressionType `
                                                        -Level $TestCase.CompressionLevel `
                                                        -numThreads $TestCase.Thread `
                                                        -numIterations $TestCase.Iteration `
                                                        -blockSize $TestCase.Block `
                                                        -Chunk $TestCase.Chunk `
                                                        -BertaResultPath $BertaResultPath `
                                                        -TestFileType $TestCase.TestFileType `
                                                        -TestFileSize $TestCase.TestFileSize `
                                                        -TestType $TestType
                                                } else {
                                                    $ParcompTestResult = WinHost-ParcompSWfallback `
                                                        -CompressType $TestCase.CompressType `
                                                        -CompressProvider $TestCase.Provider `
                                                        -deCompressProvider $TestCase.Provider `
                                                        -QatCompressionType $TestCase.CompressionType `
                                                        -Level $TestCase.CompressionLevel `
                                                        -numThreads $TestCase.Thread `
                                                        -numIterations $TestCase.Iteration `
                                                        -blockSize $TestCase.Block `
                                                        -Chunk $TestCase.Chunk `
                                                        -BertaResultPath $BertaResultPath `
                                                        -TestFileType $TestCase.TestFileType `
                                                        -TestFileSize $TestCase.TestFileSize `
                                                        -TestType $TestType
                                                }

                                                if ($ParcompTestResult.result) {
                                                    $ParcompTestResult.result = $TestResultToBerta.Pass
                                                } else {
                                                    $ParcompTestResult.result = $TestResultToBerta.Fail

                                                    if ($FailToStop) {
                                                        throw ("If test caes is failed, then stop testing.")
                                                    }
                                                }

                                                $TestCaseResultsList = [hashtable] @{
                                                    tc = $testNameTmp
                                                    s = $ParcompTestResult.result
                                                    e = $ParcompTestResult.error
                                                }

                                                WBase-WriteTestResult -TestResult $TestCaseResultsList
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if ($SmokeTestTestType -eq "Installer") {
                            $parcompFlag = $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].Parcomp
                            $cngtestFlag = $SmokeTestTypesList[$SmokeTestModeType][$SmokeTestTestType].CNGTest
                            $InstallerTypes = [System.Array] @("disable")

                            if ($parcompFlag) {$InstallerTypes += "parcomp"}
                            if ($cngtestFlag) {$InstallerTypes += "cngtest"}

                            if (-not $CompareFlag) {
                                if ($SmokeTestModeType -eq "HVMode") {
                                    $TestResultList = WTW-InstallerCheckDisable `
                                        -parcompFlag $parcompFlag `
                                        -cngtestFlag $cngtestFlag `
                                        -BertaResultPath $BertaResultPath
                                } else {
                                    $TestResultList = WinHost-InstallerCheckDisable `
                                        -parcompFlag $parcompFlag `
                                        -cngtestFlag $cngtestFlag `
                                        -BertaResultPath $BertaResultPath
                                }
                            }

                            Foreach ($InstallerType in $InstallerTypes) {
                                if ((!$parcompFlag) -and ($InstallerType -eq "parcomp")) {continue}
                                if ((!$cngtestFlag) -and ($InstallerType -eq "cngtest")) {continue}

                                $testName = "{0}_{1}" -f $testNameHeader, $InstallerType
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
                                    if ($TestResultList[$InstallerType]["result"]) {
                                        $TestResultList[$InstallerType]["result"] = $TestResultToBerta.Pass
                                    } else {
                                        $TestResultList[$InstallerType]["result"] = $TestResultToBerta.Fail

                                        if ($FailToStop) {
                                            throw ("If test caes is failed, then stop testing.")
                                        }
                                    }

                                    $TestCaseResultsList = [hashtable] @{
                                        tc = $testName
                                        s = $TestResultList[$InstallerType]["result"]
                                        e = $TestResultList[$InstallerType]["error"]
                                    }

                                    WBase-WriteTestResult -TestResult $TestCaseResultsList
                                }
                            }
                        }
                    }
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
