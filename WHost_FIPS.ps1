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

    # Check and set UQ mode
    $DisableDeviceFlag = $false
    $UQModeStatus = UT-CheckUQMode `
        -CheckFlag $true `
        -Remote $false
    if (-not $UQModeStatus) {
        $DisableDeviceFlag = $true
        UT-SetUQMode `
            -UQMode $true `
            -Remote $false | out-null
    } 

    # Check and set Services Data
    $ServicesStatus = UT-checkFIPSServicesData `
        -CheckServiceEnableFlag "sym" `
        -CheckServiceNeededFlag "sym" `
        -Remote $false
    if (-not $ServicesStatus) {
        $DisableDeviceFlag = $true
        UT-SetFIPSServicesData `
            -ServiceEnable "sym" `
            -ServiceNeeded "sym" `
            -Remote $false | out-null
    }
    
    UT-WorkAround `
        -Remote $false `
        -DisableFlag $DisableDeviceFlag | out-null

    Win-DebugTimestamp -output ("Initialize test environment....")
    WinHost-ENVInit | out-null

    Win-DebugTimestamp -output ("Start to run test case....")
    Win-DebugTimestamp -output (
        "-------------------------------------------------------------------------------------------------"
    )

    foreach ($test_group in $FIPS.batch.testGroups) {
        Win-DebugTimestamp -output ( "Started test group $($test_group.tgId)" )
    
        if ($test_group.testType -eq "AFT") {
            foreach ($test in $test_group.tests) {
                $testName = "FIPS_UQ_Host"
                $testName = "{0}_{1}_{2}_tgId_{3}_tcId_{4}" -f $testName, $($FIPS.batch.algorithm), $($test_group.direction), $($test_group.tgId), $($test.tcId)
                Win-DebugTimestamp -output (  "`t started test $($test.tcId)" )

                if([String]::IsNullOrEmpty($($test.aad))){
                    $test.aad = "tempData"
                }

                if($($test_group.direction) -eq "encrypt"){

                    if([String]::IsNullOrEmpty($($test.pt))){
                        $test.pt = "tempData"
                    }

                    $FIPSTestResult = FIPS-Entry `
                    -_tgId $($test_group.tgId) `
                    -_tcId $($test.tcId) `
                    -_direction $($test_group.direction) `
                    -_in $($test.pt) `
                    -_key $($test.key) `
                    -_iv $($test.iv) `
                    -_aad $($test.aad) `
                    -_aadLen $($test_group.aadLen) `
                    -_tagLen $($test_group.tagLen) `
                    -_payloadLen $($test_group.payloadLen) `
                    -Remote $false
                }else{

                    if([String]::IsNullOrEmpty($($test.ct))){
                        $test.ct = "tempData"
                    }

                    $FIPSTestResult = FIPS-Entry `
                    -_tgId $($test_group.tgId) `
                    -_tcId $($test.tcId) `
                    -_direction $($test_group.direction) `
                    -_in ($($test.ct)+$($test.tag)) `
                    -_key $($test.key) `
                    -_iv $($test.iv) `
                    -_aad $($test.aad) `
                    -_aadLen $($test_group.aadLen) `
                    -_tagLen $($test_group.tagLen) `
                    -_payloadLen $($test_group.payloadLen) `
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

                Win-DebugTimestamp -output ( "`t End test $($tcId)")
            }
        }
        Win-DebugTimestamp -output ( "End test group $($tgId)")
    }
}
catch {
    Win-DebugTimestamp -output $_
}
finally {
    WBase-CompareTestResult -CompareFile $CompareFile
    Win-DebugTimestamp -output ("Ending $($MyInvocation.MyCommand)")
}
