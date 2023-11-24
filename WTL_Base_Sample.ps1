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

Import-Module "$QATTESTPATH\\lib\\Win2Linux.psm1" -Force -DisableNameChecking
WBase-ReturnFilesInit `
    -BertaResultPath $BertaResultPath `
    -ResultFile $ResultFile | out-null

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
    $LocationInfo.VM.IsWin = $false
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $LocalBuildPath

    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
                           -QatDriverFullPath $PFVFDriverPath `
                           -BertaConfig $BertaConfig | out-null

    # Special: For All
    if ([String]::IsNullOrEmpty($VMVFOSConfigs)) {
        [System.Array]$VMVFOSConfigs = HV-GenerateVMVFConfig -ConfigType "Base"
    }

    Foreach ($VMVFOSConfig in $VMVFOSConfigs) {
        if ($LocationInfo.UQMode) {
            $UQString = "UQ"
        } else {
            $UQString = "NUQ"
        }

        $testNameHeader = "Regression_WTL_{0}_{1}_{2}_Base_Sample" -f
            $LocationInfo.QatType,
            $UQString,
            $VMVFOSConfig

        Win-DebugTimestamp -output ("Initialize test environment....")
        WTL-ENVInit -VMVFOSConfig $VMVFOSConfig -InitVM $InitVM| out-null

        Win-DebugTimestamp -output ("Start to run test case....")
        $RunTestResult = WTL-BaseSample
        $testName = "{0}_Run_Linux_Shell" -f $testNameHeader
        if ($RunTestResult.result) {
            $RunTestResult.result = $TestResultToBerta.Pass
        } else {
            $RunTestResult.result = $TestResultToBerta.Fail

            if ($FailToStop) {
                throw ("If test caes is failed, then stop testing.")
            }
        }

        $TestCaseResultsList = [hashtable] @{
            tc = $testName
            s = $RunTestResult.result
            e = $RunTestResult.error
        }

        WBase-WriteTestResult -TestResult $TestCaseResultsList

        if ($RunTestResult.result) {
            Win-DebugTimestamp -output ("Start to check test case result....")
            $TestResultList = WTL-CheckOutput
            Foreach ($TestResult in $TestResultList) {
                $testName = "{0}_{1}" -f $testNameHeader, $TestResult.name
                if ($TestResult.result) {
                    $TestResult.result = $TestResultToBerta.Pass
                } else {
                    $TestResult.result = $TestResultToBerta.Fail

                    if ($FailToStop) {
                        throw ("If test caes is failed, then stop testing.")
                    }
                }

                $LocationInfo.TestCaseName = $testName
                $TestCaseResultsList = [hashtable] @{
                    tc = $testName
                    s = $TestResult.result
                    e = $TestResult.error
                }

                WBase-WriteTestResult -TestResult $TestCaseResultsList
            }
        }
    }
} catch {
    Win-DebugTimestamp -output $_
} finally {
    Win-DebugTimestamp -output ("Ending $($MyInvocation.MyCommand)")
}
