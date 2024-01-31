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

    [System.Array]$CompareTypes = ("true", "false")

    $batch = Get-Content -Path $FIPS.FIPSSamplePath | ConvertFrom-Json
    $batchResult = [hashtable] @{}
    $batchResult["vsId"] = $batch.vsId
    $batchResult["algorithm"] = $batch.algorithm
    $batchResult["revision"] = $batch.revision
    $batchResult["isSample"] = $batch.isSample
    $batchResult["testGroups"] = [System.Array] @()

    $TestCaseHashtable = WBase-ReadHashtableFromJsonFile -InfoFilePath $FIPS.FIPSSamplePath
    
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
            FIPS-ENV `
                -BertaResultPath $BertaResultPath `
                -ResultJsonFile "ACVP-AES-GCM-response.json" `
                -ENVType "init" | out-null

            Win-DebugTimestamp -output ("Start to run test case....")
            Win-DebugTimestamp -output ("-------------------------------------------------------------------------------------------------")
        }

        foreach ($testGroup in $TestCaseHashtable.testGroups) {
            Win-DebugTimestamp -output ( "Started test group {0}" -f $testGroup.tgId )
            
            $testGroupResultJson = [hashtable] @{}
            $testGroupResultJson["tgId"] = $testGroup.tgId
            $testGroupResultJson["tests"] = [System.Array] @()
            $testCaseFirstIteration = $true 
            
            if ($testGroup.testType -eq "AFT") {
                foreach ($test in $testGroup.tests) {
                    $testCaseResultJson = [hashtable] @{}
                    $testCaseResultJson["tcId"] = $test.tcId

                    $testNameHeader = "FIPS_UQ_Host"
                    $testName = "{0}_{1}_TestGroup_{2}_{3}_TestCase_{4}" -f 
                        $testNameHeader, 
                        $TestCaseHashtable.algorithm, 
                        $testGroup.tgId, 
                        $testGroup.direction,
                        $test.tcId

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
                        Win-DebugTimestamp -output (  " started test {0}" -f $test.tcId )
                        $LocationInfo.TestCaseName = $testName

                        if ([String]::IsNullOrEmpty($test.aad)) {
                            $test.aad = "tempData"
                        }
                        if ($testGroup.direction -eq "encrypt") {
                            $InputValue = [hashtable] @{
                                InFileContent   = $test.pt
                                KeyFileContent  = $test.key
                                IvFileContent   = $test.iv
                                AadFileContent  = $test.aad
                            }
                            WBase-WriteHashtableToJsonFile `
                                -Info $InputValue `
                                -InfoFilePath $FIPS.InputValuePath | out-null
        
                            if ([String]::IsNullOrEmpty($test.pt)) {
                                $test.pt = "tempData"
                            }
                            $FIPSTestResult = FIPS-Entry `
                                -TestGroupId $testGroup.tgId `
                                -TestCaseId $test.tcId `
                                -EncryptDecryptDirection $testGroup.direction `
                                -InputValuePath $FIPS.InputValuePath `
                                -AadLen $testGroup.aadLen `
                                -TagLen $testGroup.tagLen `
                                -PayloadLen $testGroup.payloadLen `
                                -Remote $false
        
                            $TestCaseResultHashtable = WBase-ReadHashtableFromJsonFile `
                                -InfoFilePath $FIPS.TestCaseJsonPath
                            $testCaseResultJson["ct"] = $TestCaseResultHashtable.ct
                            $testCaseResultJson["tag"] = $TestCaseResultHashtable.tag
                        }
                        else {
                            $InputValue = [hashtable] @{
                                InFileContent   = ($test.ct + $test.tag)
                                KeyFileContent  = $test.key
                                IvFileContent   = $test.iv
                                AadFileContent  = $test.aad
                            }
                            WBase-WriteHashtableToJsonFile `
                                -Info $InputValue `
                                -InfoFilePath $FIPS.InputValuePath | out-null
        
                            if ([String]::IsNullOrEmpty($test.ct)) {
                                $test.ct = "tempData"
                            }
                            $FIPSTestResult = FIPS-Entry `
                                -TestGroupId $testGroup.tgId `
                                -TestCaseId $test.tcId `
                                -EncryptDecryptDirection $testGroup.direction `
                                -InputValuePath $FIPS.InputValuePath `
                                -AadLen $testGroup.aadLen `
                                -TagLen $testGroup.tagLen `
                                -PayloadLen $testGroup.payloadLen `
                                -Remote $false
        
                            $TestCaseResultHashtable = WBase-ReadHashtableFromJsonFile `
                                -InfoFilePath $FIPS.TestCaseJsonPath
                            $testCaseResultJson["pt"] = $TestCaseResultHashtable.pt
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
                        $testGroupResultJson["tests"] += $testCaseResultJson
                        Win-DebugTimestamp -output ( " End test {0}" -f $test.tcId)
        
                        if($testCaseFirstIteration){
                            $batchResult["testGroups"] += $testGroupResultJson
                            $testCaseFirstIteration = $false
                        }
                        WBase-WriteHashtableToJsonFile `
                        -Info $batchResult `
                        -InfoFilePath $FIPSResultJsonFile | out-null
                    }
                }
            }
            Win-DebugTimestamp -output ( "End test group {0}" -f $testGroup.tgId)
        }

        if ($CompareFlag) {
            Win-DebugTimestamp -output (
                "Complete compare file: {0}" -f $CompareFile
            )
        }
    }
}
catch {
    Win-DebugTimestamp -output $_
}
finally {
    WBase-CompareTestResult -CompareFile $CompareFile
    Win-DebugTimestamp -output ("Ending $($MyInvocation.MyCommand)")
}
