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

        $BertaConfig["UQ_mode"] = ($out.config.UQ_mode -eq "true") ? $true : $false
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

    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
                           -QatDriverFullPath $PFVFDriverPath `
                           -BertaConfig $BertaConfig | out-null

    [System.Array]$CompareTypes = ("true", "false")

    # Special: For All
    [System.Array]$Providers = (
        [hashtable] @{
            CompressProvider = "qatgzip"
            deCompressProvider = "7zip"
        },
        [hashtable] @{
            CompressProvider = "qatgzipext"
            deCompressProvider = "7zip"
        },
        [hashtable] @{
            CompressProvider = "qatgzipext"
            deCompressProvider = "qatgzip"
        },
        [hashtable] @{
            CompressProvider = "qat"
            deCompressProvider = "igzip"
        }
    )

    $deCompressFlag = $false
    $QatCompressionType = "dynamic"
    $CompressionLevel = 1
    $ChunkSize = 64
    $TestPathName = "ParcompTest"
    $TestFileType = "calgary"
    $TestFileSize = 200
    $TestType = "Compat"

    if ([String]::IsNullOrEmpty($VMVFOSConfigs)) {
        [System.Array]$VMVFOSConfigs = HV-GenerateVMVFConfig -ConfigType "Base"
    }

    # Special: For QAT17
    if ($LocationInfo.QatType -eq "QAT17") {
        if ($LocationInfo.UQMode) {
            throw ("QAT17: On the HVMode, not support UQ Mode.")
        }

        [System.Array]$Providers = (
            [hashtable] @{
                CompressProvider = "qatgzip"
                deCompressProvider = "7zip"
            },
            [hashtable] @{
                CompressProvider = "qatgzipext"
                deCompressProvider = "7zip"
            }
        )
    }

    # Special: For QAT18
    if ($LocationInfo.QatType -eq "QAT18") {
        if ($LocationInfo.UQMode) {
            throw ("QAT18: On the HVMode, not support UQ Mode.")
        }

        [System.Array]$Providers = (
            [hashtable] @{
                CompressProvider = "qatgzip"
                deCompressProvider = "7zip"
            },
            [hashtable] @{
                CompressProvider = "qatgzipext"
                deCompressProvider = "7zip"
            }
        )
    }

    # Special: For QAT20
    if ($LocationInfo.QatType -eq "QAT20") {
        if ($LocationInfo.UQMode) {
            throw ("QAT20: On the HVMode, not support UQ Mode.")
        }
    }

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
            $UQString = ($LocationInfo.UQMode) ? "UQ" : "NUQ"
            $testNameHeader = "Regression_WTW_{0}_{1}_{2}_Base_Compat" -f
                $LocationInfo.QatType,
                $UQString,
                $VMVFOSConfig

            if (-not $CompareFlag) {
                Win-DebugTimestamp -output ("Initialize test environment....")
                WTW-ENVInit -VMVFOSConfig $VMVFOSConfig -InitVM $InitVM | out-null

                Win-DebugTimestamp -output ("Start to run test case....")
            }

            Foreach ($Provider in $Providers) {
                $CompressProvider = $Provider.CompressProvider
                $deCompressProvider = $Provider.deCompressProvider
                $testName = "{0}_compress_{1}_decompress_{2}" -f
                    $testNameHeader,
                    $CompressProvider,
                    $deCompressProvider

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
                    $LocationInfo.TestCaseName = $testName

                    $ParcompBaseTestResult = WTW-ParcompBase `
                        -deCompressFlag $deCompressFlag `
                        -CompressProvider $CompressProvider `
                        -deCompressProvider $deCompressProvider `
                        -QatCompressionType $QatCompressionType `
                        -Level $CompressionLevel `
                        -Chunk $ChunkSize `
                        -TestPathName $TestPathName `
                        -TestFilefullPath $SourceFile `
                        -BertaResultPath $BertaResultPath `
                        -TestFileType $TestFileType `
                        -TestFileSize $TestFileSize `
                        -TestType $TestType

                    if (-not ([string]($ParcompBaseTestResult.gettype()) -eq "hashtable")) {
                        $ParcompBaseTestResult = $ParcompBaseTestResult[-1]
                    }

                    if ($ParcompBaseTestResult.result) {
                        $ParcompBaseTestResult.result = $TestResultToBerta.Pass
                    } else {
                        $ParcompBaseTestResult.result = $TestResultToBerta.Fail

                        if ($FailToStop) {
                            throw ("If test caes is failed, then stop testing.")
                        }
                    }

                    $TestCaseResultsList = [hashtable] @{
                        tc = $testName
                        s = $ParcompBaseTestResult.result
                        e = $ParcompBaseTestResult.error
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
