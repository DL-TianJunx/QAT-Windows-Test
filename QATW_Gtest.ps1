Param(
    [Parameter(Mandatory=$True)]
    [string]$BertaResultPath,

    [string]$TestType = "compress_multi_process",

    [bool]$RunOnLocal = $false,

    [bool]$InitVM = $true,

    [array]$VMVFOSConfigs = $null,

    [bool]$HVMode = $false,

    [bool]$UQMode = $false,

    [bool]$TestMode = $true,

    [bool]$VerifierMode = $true,

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
        $BertaConfig["HV_mode"] = $HVMode
        $BertaConfig["UQ_mode"] = $UQMode
        $BertaConfig["test_mode"] = $TestMode
        $BertaConfig["driver_verifier"] = $VerifierMode
        $BertaConfig["DebugMode"] = $DebugMode
        $LocationInfo.WriteLogToConsole = $true
        $LocalBuildPath = $DriverPath
    } else {
        $FilePath = Join-Path -Path $BertaResultPath -ChildPath "task.json"
        $out = Get-Content -LiteralPath $FilePath | ConvertFrom-Json -AsHashtable

        if ($out.config.HV_mode -eq "true") {
            $BertaConfig["HV_mode"] = $true
        } else {
            $BertaConfig["HV_mode"] = $false
        }

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
        $TestType = $out.config.test_type

        $job2 = $out.jobs | Where-Object {$_.job_id -eq 2}
        $LocalBuildPath = $job2.bld_path
    }

    $LocationInfo.IsWin = $true
    $LocationInfo.VM.IsWin = $true
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $LocalBuildPath

    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
                           -QatDriverFullPath $PFVFDriverPath `
                           -BertaConfig $BertaConfig | out-null

    # Special: For All
    $ConfigType = "Gtest"
    $ListFlag = $false

    if ($LocationInfo.HVMode) {
        $Remote = $true
        $Platform = "HV"
        if ([String]::IsNullOrEmpty($VMVFOSConfigs)) {
            [System.Array]$VMVFOSConfigs = HV-GenerateVMVFConfig -ConfigType $ConfigType
        }
    } else {
        $Remote = $false
        if ($LocationInfo.UQMode) {
            $Platform = "UQ"
        } else {
            $Platform = "NUQ"
        }
        [System.Array]$VMVFOSConfigs = ("Host")
    }

    Foreach ($VMVFOSConfig in $VMVFOSConfigs) {
        $testNameHeader = "{0}_{1}_{2}" -f
            $ConfigType,
            $Platform,
            $VMVFOSConfig

        Win-DebugTimestamp -output ("Initialize test environment....")
        if ($Remote) {
            WTW-ENVInit `
                -VMVFOSConfig $VMVFOSConfig `
                -InitVM $InitVM `
                -VMSwitchType "External" | out-null

            if ($InitVM) {
                Gtest-ENV -ENVType "init" | out-null
            }
        } else {
            WinHost-ENVInit | out-null
            Gtest-ENV -ENVType "init" | out-null
        }

        Win-DebugTimestamp -output ("Start to run test case....")
        Win-DebugTimestamp -output (
            "-------------------------------------------------------------------------------------------------"
        )

        $GtestTestResult = Gtest-Entry `
            -Remote $Remote `
            -TestType $TestType `
            -ListFlag $ListFlag

        if ($GtestTestResult.result) {
            Foreach ($testcases in $GtestTestResult.testcases) {
                $testName = "{0}_{1}" -f $testNameHeader, $testcases.name
                if ($testcases.result) {
                    $testcases.result = $TestResultToBerta.Pass
                } else {
                    $testcases.result = $TestResultToBerta.Fail
                }

                $TestCaseResultsList = [hashtable] @{
                    tc = $testName
                    s = $testcases.result
                    e = $testcases.error
                }

                WBase-WriteTestResult -TestResult $TestCaseResultsList
            }
        } else {
            Win-DebugTimestamp -output (
                "The test '{0}' is failed > {1}" -f
                    $testNameHeader,
                    $GtestTestResult.error
            )

            if ($FailToStop) {
                throw ("If test caes is failed, then stop testing.")
            }
        }
    }
} catch {
    Win-DebugTimestamp -output $_
} finally {
    if ($InitVM) {
        Gtest-ENV -ENVType "clear" | out-null
    }
    WBase-CompareTestResult -CompareFile $CompareFile
    Win-DebugTimestamp -output ("Ending $($MyInvocation.MyCommand)")
}
