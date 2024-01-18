Param(
    [Parameter(Mandatory = $True)]
    [string]$BertaResultPath,

    [bool]$RunOnLocal = $false,

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
        $BertaConfig["UQ_mode"] = $UQMode
        $BertaConfig["test_mode"] = $TestMode
        $BertaConfig["driver_verifier"] = $VerifierMode
        $BertaConfig["DebugMode"] = $DebugMode
        $LocationInfo.WriteLogToConsole = $true
        $LocalBuildPath = $DriverPath
    }
    else {
        $FilePath = Join-Path -Path $BertaResultPath -ChildPath "task.json"
        $out = Get-Content -LiteralPath $FilePath | ConvertFrom-Json -AsHashtable

        if ($out.config.UQ_mode -eq "true") {
            $BertaConfig["UQ_mode"] = $true
        }
        else {
            $BertaConfig["UQ_mode"] = $false
        }

        if ($out.config.test_mode -eq "true") {
            $BertaConfig["test_mode"] = $true
        }
        else {
            $BertaConfig["test_mode"] = $false
        }

        if ($out.config.driver_verifier -eq "true") {
            $BertaConfig["driver_verifier"] = $true
        }
        else {
            $BertaConfig["driver_verifier"] = $false
        }

        $BertaConfig["DebugMode"] = $false

        $job2 = $out.jobs | Where-Object { $_.job_id -eq 2 }
        $LocalBuildPath = $job2.bld_path
    }

    $LocationInfo.HVMode = $false
    $LocationInfo.IsWin = $true
    $LocationInfo.VM.IsWin = $null
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $LocalBuildPath

    WBase-LocationInfoInit -BertaResultPath $BertaResultPath `
        -QatDriverFullPath $PFVFDriverPath `
        -BertaConfig $BertaConfig | out-null

    Win-DebugTimestamp -output ("Initialize test environment....")
    WinHost-ENVInit | out-null
    FIPS-ENV -ENVType "init" | out-null

    Win-DebugTimestamp -output ("Start to run test case....")
    Win-DebugTimestamp -output (
        "-------------------------------------------------------------------------------------------------"
    )

    $TestCaseHashtable = WBase-ReadHashtableFromJsonFile -InfoFilePath $FIPS.FIPSSamplePath

    foreach ($testGroup in $TestCaseHashtable.testGroups) {
        Win-DebugTimestamp -output ( "Started test group {0}" -f $testGroup.tgId )
    
        if ($testGroup.testType -eq "AFT") {
            foreach ($test in $testGroup.tests) {
                $testName = "FIPS_UQ_Host"
                $testName = "{0}_{1}_{2}_TestGroup_{3}_TestCase_{4}" -f 
                    $testName, 
                    $TestCaseHashtable.algorithm, 
                    $testGroup.direction, 
                    $testGroup.tgId, 
                    $test.tcId
                Win-DebugTimestamp -output (  "`t started test {0}" -f $test.tcId )
                if ([String]::IsNullOrEmpty($test.aad)) {
                    $test.aad = "tempData"
                }
                if ($testGroup.direction -eq "encrypt") {
                    if ([String]::IsNullOrEmpty($test.pt)) {
                        $test.pt = "tempData"
                    }
                    $FIPSTestResult = FIPS-Entry `
                        -TestGroupId $testGroup.tgId `
                        -TestCaseId $test.tcId `
                        -EncryptDecryptDirection $testGroup.direction `
                        -InFileContent $test.pt `
                        -KeyFileContent $test.key `
                        -IvFileContent $test.iv `
                        -AadFileContent $test.aad `
                        -AadLen $testGroup.aadLen `
                        -TagLen $testGroup.tagLen `
                        -PayloadLen $testGroup.payloadLen `
                        -Remote $false
                }
                else {
                    if ([String]::IsNullOrEmpty($test.ct)) {
                        $test.ct = "tempData"
                    }
                    $FIPSTestResult = FIPS-Entry `
                        -TestGroupId $testGroup.tgId `
                        -TestCaseId $test.tcId `
                        -EncryptDecryptDirection $testGroup.direction `
                        -InFileContent ($test.ct + $test.tag) `
                        -KeyFileContent $test.key `
                        -IvFileContent $test.iv `
                        -AadFileContent $test.aad `
                        -AadLen $testGroup.aadLen `
                        -TagLen $testGroup.tagLen `
                        -PayloadLen $testGroup.payloadLen `
                        -Remote $false
                }

                if ($FIPSTestResult.result) {
                    $FIPSTestResult.result = $TestResultToBerta.Pass
                }
                else {
                    $FIPSTestResult.result = $TestResultToBerta.Fail

                    Win-DebugTimestamp -output (
                        "The test '{0}' is failed > {1}" -f
                            $testName,
                            $FIPSTestResult.error
                    )
                    if ($FailToStop) {
                        throw ("If test caes is failed, then stop testing.")
                    }
                }

                $TestCaseResultsList = [hashtable] @{
                    tc = $testName
                    s  = $FIPSTestResult.result
                    e  = $FIPSTestResult.error
                }

                WBase-WriteTestResult -TestResult $TestCaseResultsList

                Win-DebugTimestamp -output ( "`t End test {0}" -f $test.tcId)
            }
        }
        Win-DebugTimestamp -output ( "End test group {0}" -f $testGroup.tgId)
    }
}
catch {
    Win-DebugTimestamp -output $_
}
finally {
    WBase-CompareTestResult -CompareFile $CompareFile
    Win-DebugTimestamp -output ("Ending $($MyInvocation.MyCommand)")
}
