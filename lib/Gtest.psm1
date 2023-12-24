
$global:Gtest = [hashtable] @{
    GtestPath = "{0}\Gtest" -f $QATTESTPATH
    SourcePath = "\\10.67.115.211\mountBertaCTL\GTest"
    ServiceName = "qzfor"
    TestScriptName = "qat_gtest"
    TestType = [System.Array] @(
        "compress_multi_process",
        "compress_kernel",
        "compress_positive",
        "compress_negative"
    )
}

# About ENVInit
function Gtest-ProcessENVInit
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [string]$VMNameSuffix
    )

    Start-Sleep -Seconds 5

    WBase-GetInfoFile | out-null

    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    if ($Remote) {
        $VMName = ("{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix)
        $PSSessionName = ("Session_{0}" -f $VMNameSuffix)
        $Session = HV-PSSessionCreate `
            -VMName $VMName `
            -PSName $PSSessionName `
            -IsWin $true `
            -CheckFlag $false

        $LogKeyWord = $PSSessionName
    } else {
        $LogKeyWord = "Host"
    }

    # Ready test file
    $QualifierName = "D"
    $LocalTestSuite = "{0}:\CompressionFiles" -f $QualifierName
    Win-DebugTimestamp -output (
        "{0}: Prepare test files > {1}" -f
            $LogKeyWord,
            $LocalTestSuite
    )

    $ScriptBlock = {
        Param($SourcePath, $QualifierName)

        $ReturnValue = $false

        $QualifierPath = "{0}:\" -f $QualifierName
        $CopyPath = "{0}\CompressionFiles\*" -f $SourcePath
        $DestinationPath = "{0}:\CompressionFiles" -f $QualifierName

        if (Test-Path -Path $SourcePath) {
            if (Test-Path -Path $QualifierPath) {
                $DisplayRoot = (Get-PSDrive -Name $QualifierName).DisplayRoot
                if ($DisplayRoot -ne $SourcePath) {
                    Copy-Item `
                        -Path $CopyPath `
                        -Destination $DestinationPath `
                        -Recurse `
                        -Force `
                        -Confirm:$false `
                        -ErrorAction Stop | out-null
                }
            } else {
                New-PSDrive `
                    -Name $QualifierName `
                    -Root $SourcePath `
                    -Persist `
                    -PSProvider "FileSystem" `
                    -Scope Global | out-null
            }
        }

        if (Test-Path -Path $DestinationPath) {
            $ReturnValue = $true
        }

        return $ReturnValue
    }

    if ($Remote) {
        $PrepareStatus = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $Gtest.SourcePath, $QualifierName
    } else {
        $PrepareStatus = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $Gtest.SourcePath, $QualifierName
    }

    if ($PrepareStatus) {
        Win-DebugTimestamp -output (
            "{0}: Prepare test files > passed" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Prepare test files > failed" -f $LogKeyWord
        )
    }

    # Ready test script(US STV)
    $ShareTestSuite = "{0}\QatTestBerta" -f (Split-Path -Parent $Gtest.SourcePath)
    $LocalTestSuite = "C:\QatTestBerta"
    Win-DebugTimestamp -output (
        "{0}: Prepare test script > {1}" -f
            $LogKeyWord,
            $LocalTestSuite
    )

    $ScriptBlock = {
        Param($ShareTestSuite, $LocalTestSuite)

        $ReturnValue = $false

        if (Test-Path -Path $LocalTestSuite) {
            Get-Item -Path $LocalTestSuite | Remove-Item -Recurse -Force | out-null
        }
        New-Item -Path $LocalTestSuite -ItemType Directory | out-null

        $CopyPath = "{0}\\*" -f $ShareTestSuite
        Copy-Item `
            -Path $CopyPath `
            -Destination $LocalTestSuite `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null

        if (Test-Path -Path $LocalTestSuite) {
            $ReturnValue = $true
        }

        return $ReturnValue
    }

    if ($Remote) {
        $PrepareStatus = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ShareTestSuite, $LocalTestSuite
    } else {
        $PrepareStatus = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ShareTestSuite, $LocalTestSuite
    }

    if ($PrepareStatus) {
        Win-DebugTimestamp -output (
            "{0}: Prepare test script > passed" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Prepare test script > failed" -f $LogKeyWord
        )
    }

    # Ready test script(Gtest)
    $ShareTestSuite = "{0}\{1}" -f $Gtest.SourcePath, $Gtest.TestScriptName
    $LocalTestSuite = "C:\{0}" -f $Gtest.TestScriptName
    Win-DebugTimestamp -output (
        "{0}: Prepare test script > {1}" -f
            $LogKeyWord,
            $LocalTestSuite
    )

    if ($Remote) {
        $PrepareStatus = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ShareTestSuite, $LocalTestSuite
    } else {
        $PrepareStatus = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ShareTestSuite, $LocalTestSuite
    }

    if ($PrepareStatus) {
        Win-DebugTimestamp -output (
            "{0}: Prepare test script > passed" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Prepare test script > failed" -f $LogKeyWord
        )
    }

    # Ready test include and library file
    $IncludeFileArray = @()
    $IncludeFileArray += "qatzip.h"
    $LibFileArray = @()
    $LibFileArray += "libqatzip.lib"
    $LibFileArray += "qatzip.lib"

    Win-DebugTimestamp -output (
        "{0}: Prepare test include and library file" -f $LogKeyWord
    )

    $ScriptBlock = {
        Param($IncludeFileArray, $LibFileArray)

        $GtestIncludePath = "C:\qat_gtest\shared\include"
        $GTestLibPath = "C:\qat_gtest\shared\lib"

        $IncludeFileArray | ForEach-Object {
            $GTestIncludeFile = "{0}\{1}" -f $GtestIncludePath, $_
            $IncludeFile = "C:\Program Files\Intel\Intel(R) QuickAssist Technology\Compression\Library\{0}" -f $_
            if (Test-Path -Path $GTestIncludeFile) {
                Get-Item -Path $GTestIncludeFile | Remove-Item -Force | out-null
            }
            Copy-Item -Path $IncludeFile -Destination $GTestIncludeFile
        }

        $LibFileArray | ForEach-Object {
            $GTestLibFile = "{0}\{1}" -f $GTestLibPath, $_
            $LibFile = "C:\Program Files\Intel\Intel(R) QuickAssist Technology\Compression\Library\{0}" -f $_
            if (Test-Path -Path $GTestLibFile) {
                Get-Item -Path $GTestLibFile | Remove-Item -Force | out-null
            }
            Copy-Item -Path $LibFile -Destination $GTestLibFile
        }
    }

    if ($Remote) {
        Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $IncludeFileArray, $LibFileArray | out-null
    } else {
        Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $IncludeFileArray, $LibFileArray | out-null
    }

    Win-DebugTimestamp -output (
        "{0}: Prepare test include and library file > passed" -f $LogKeyWord
    )

    if ($Remote) {
        # Ready gtest app
        $GtestAppNameArray = @(
            "qatzip_gtest.exe",
            "qatzipd_gtest.exe",
            "qatzipkm_gtest"
        )

        Foreach ($GtestAppName in $GtestAppNameArray) {
            $ProcessFilePath = "{0}\\{1}" -f $Gtest.GtestPath, $GtestAppName
            $ProcessFilePathDestination = "{0}\\{1}" -f $STVWinPath, $GtestAppName
            if (Test-Path -Path $ProcessFilePath) {
                Copy-Item `
                    -ToSession $Session `
                    -Path $ProcessFilePath `
                    -Destination $ProcessFilePathDestination `
                    -Force `
                    -Confirm:$false | out-null
            }
        }
    } else {
        # Start qzfor server
        $ServiceFile = "{0}\\{1}.sys" -f $Gtest.GtestPath, $Gtest.ServiceName
        $ServiceCert = "{0}\\{1}.cer" -f $Gtest.GtestPath, $Gtest.ServiceName
        if ($Remote) {
            UT-CreateService `
                -ServiceName $Gtest.ServiceName `
                -ServiceFile $ServiceFile `
                -ServiceCert $ServiceCert `
                -Remote $Remote `
                -Session $Session | out-null
        } else {
            UT-CreateService `
                -ServiceName $Gtest.ServiceName `
                -ServiceFile $ServiceFile `
                -ServiceCert $ServiceCert `
                -Remote $Remote | out-null
        }
    }
}

function Gtest-ENVInit
{
    WBase-GenerateInfoFile | out-null

    $ProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()
    $PlatformList = [System.Array] @()
    if ($LocationInfo.HVMode) {
        $PlatformList = $LocationInfo.VM.NameArray
    } else {
        $PlatformList += "Host"
    }

    # Start process of ENVInit
    $PlatformList | ForEach-Object {
        if ($LocationInfo.HVMode) {
            $LogKeyWord = "{0}_{1}" -f $env:COMPUTERNAME, $_
            $GtestInitProcessArgs = "Gtest-ProcessENVInit -Remote 1"
            $GtestInitProcessArgs = "{0} -VMNameSuffix {1}" -f $GtestInitProcessArgs, $_
        } else {
            $LogKeyWord = "Host"
            $GtestInitProcessArgs = "Gtest-ProcessENVInit -Remote 0"
        }

        $GtestInitProcesskeyWords = "Gtest_init_{0}" -f $_

        $GtestInitProcess = WBase-StartProcess `
            -ProcessFilePath "pwsh" `
            -ProcessArgs $GtestInitProcessArgs `
            -keyWords $GtestInitProcesskeyWords

        $ProcessList[$_] = [hashtable] @{
            ID = $GtestInitProcess.ID
            Output = $GtestInitProcess.Output
            Error = $GtestInitProcess.Error
            Result = $GtestInitProcess.Result
        }

        $ProcessIDArray += $GtestInitProcess.ID
    }

    # Wait Gtest ENV Init process completed
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null

    # Check output and error log for Gtest ENV Init process
    $PlatformList | ForEach-Object {
        $GtestInitProcesskeyWords = "Gtest_init_{0}" -f $_
        $ProcessResult = WBase-CheckProcessOutput `
            -ProcessOutputLogPath $ProcessList[$_].Output `
            -ProcessErrorLogPath $ProcessList[$_].Error `
            -CheckResultFlag $false `
            -Remote $false `
            -keyWords $GtestInitProcesskeyWords
    }
}

# About handle test result
function Gtest-GetTestCases
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$TestResultPath,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testcases = [System.Array] @()
    }

    $TestCaseTemplate = [hashtable] @{
        name = $null
        result = $null
        error = "no_error"
    }

    if ($Remote) {
        $TestResultContent = Invoke-Command -Session $Session -ScriptBlock {
            Param($TestResultPath)
            if (Test-Path -Path $TestResultPath) {
                $ReturnValue = Get-Content -Path $TestResultPath
            } else {
                $ReturnValue = $null
            }

            return $ReturnValue
        } -ArgumentList $TestResultPath
    } else {
        $TestResultContent = Invoke-Command -ScriptBlock {
            Param($TestResultPath)
            if (Test-Path -Path $TestResultPath) {
                $ReturnValue = Get-Content -Path $TestResultPath
            } else {
                $ReturnValue = $null
            }

            return $ReturnValue
        } -ArgumentList $TestResultPath
    }

    $PassNumber = 0
    $FailNumber = 0
    $TotalNumber = 0
    ForEach ($TestResultLine in $TestResultContent) {
        $TestResultLine = $TestResultLine -replace "\s{2,}", " "
        $TestResultLineTmp = $TestResultLine.split(" ] ")[1]

        if (-not [String]::IsNullOrEmpty($TestResultLineTmp)) {
            if ($TestResultLine -match " RUN ") {
                $TestCaseTemplate.name = $TestResultLineTmp
                $TotalNumber += 1
                Win-DebugTimestamp -output ("Test case: {0}" -f $TotalNumber)
                Win-DebugTimestamp -output ("     name: {0}" -f $TestCaseTemplate.name)
            }

            if ($TestResultLine -match " OK ") {
                $TestCaseName = $TestResultLineTmp.split(" (")[0]
                if ($TestCaseName -eq $TestCaseTemplate.name) {
                    Win-DebugTimestamp -output ("   Result: passed")
                    $TestCaseTemplate.result = $true
                    $PassNumber += 1
                    $ReturnValue.testcases += $TestCaseTemplate

                    $TestCaseTemplate = [hashtable] @{
                        name = $null
                        result = $null
                        error = "no_error"
                    }
                }
            }

            if ($TestResultLine -match " FAILED ") {
                $TestCaseName = $TestResultLineTmp.split(", ")[0]
                $TestCaseError = $TestResultLineTmp.split(", ")[1]
                if ($TestCaseName -eq $TestCaseTemplate.name) {
                    Win-DebugTimestamp -output ("   Result: failed")
                    $TestCaseTemplate.result = $false
                    $TestCaseTemplate.error = $TestCaseError
                    $FailNumber += 1
                    $ReturnValue.testcases += $TestCaseTemplate

                    $TestCaseTemplate = [hashtable] @{
                        name = $null
                        result = $null
                        error = "no_error"
                    }
                }
            }

            if ($TestResultLine -match "==========") {
                $TotalResult = $TestResultLineTmp
                Win-DebugTimestamp -output (" Total: {0}" -f $TotalResult)
                $TotalResult = $TotalResult.split(" tests")[0]
                $TotalResult = $TotalResult.split(" ")[0]
                if ($TotalResult -ne "Running") {
                    if ([int]($TotalResult) -ne $TotalNumber) {
                        Win-DebugTimestamp -output ("   Get: {0}" -f $TotalNumber)
                        if ($ReturnValue.result) {
                            $ReturnValue.result = $false
                            $ReturnValue.error = "total_number_error"
                        }
                    }
                }
            }

            if ($TestResultLine -match " PASSED ") {
                $PassResult = $TestResultLineTmp
                $PassResult = $PassResult.split(" tests")[0]
                Win-DebugTimestamp -output ("Passed: {0}" -f $PassResult)
                if ([int]$PassResult -ne $PassNumber) {
                    Win-DebugTimestamp -output ("   Get: {0}" -f $PassNumber)
                    if ($ReturnValue.result) {
                        $ReturnValue.result = $false
                        $ReturnValue.error = "pass_number_error"
                    }
                }
            }
        }
    }

    return $ReturnValue
}

function Gtest-CheckProcessOutput
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ProcessOutputLogPath,

        [Parameter(Mandatory=$True)]
        [string]$ProcessErrorLogPath,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testcases = [System.Array] @()
    }

    $ScriptBlock = {
        Param($ProcessOutputLogPath, $ProcessErrorLogPath)

        $ReturnValue = [hashtable] @{
            result = $true
            error = "no_error"
        }

        if (Test-Path -Path $ProcessOutputLogPath) {
            $ProcessOutputLog = Get-Content -Path $ProcessOutputLogPath -Raw
        } else {
            $ProcessOutputLog = $null
        }

        if (Test-Path -Path $ProcessErrorLogPath) {
            $ProcessErrorLog = Get-Content -Path $ProcessErrorLogPath -Raw
        } else {
            $ProcessErrorLog = $null
        }

        if ([String]::IsNullOrEmpty($ProcessOutputLog)) {
            if ([String]::IsNullOrEmpty($ProcessErrorLog)) {
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "no_output"
                }
            } else {
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "process_error"
                }
            }
        } else {
            if (-not [String]::IsNullOrEmpty($ProcessErrorLog)) {
                if ($ReturnValue.result) {
                    $ReturnValue.result = $false
                    $ReturnValue.error = "process_error"
                }
            }
        }

        return $ReturnValue
    }

    if ($Remote) {
        $CheckResult = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ProcessOutputLogPath, $ProcessErrorLogPath
    } else {
        $CheckResult = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ProcessOutputLogPath, $ProcessErrorLogPath
    }

    if ($CheckResult.result) {
        if ($Remote) {
            $ReturnValue = Gtest-GetTestCases `
                -TestResultPath $ProcessOutputLogPath `
                -Remote $Remote `
                -Session $Session
        } else {
            $ReturnValue = Gtest-GetTestCases `
                -TestResultPath $ProcessOutputLogPath `
                -Remote $Remote
        }
    } else {
        $ReturnValue.result = $CheckResult.result
        $ReturnValue.error = $CheckResult.error
    }

    # Copy outputlog and errorlog files to BertaResultPath
    $BertaResultProcessPath = "{0}\\Process" -f $LocationInfo.BertaResultPath
    if (-not (Test-Path -Path $BertaResultProcessPath)) {
        New-Item -Path $BertaResultProcessPath -ItemType Directory | out-null
    }

    $ProcessOutputLogName = Split-Path -Path $ProcessOutputLogPath -Leaf
    $ProcessOutputLogDestination = "{0}\\{1}" -f
        $BertaResultProcessPath,
        $ProcessOutputLogName
    if (Test-Path -Path $ProcessOutputLogDestination) {
        Remove-Item -Path $ProcessOutputLogDestination -Force | out-null
    }

    $ProcessErrorLogName = Split-Path -Path $ProcessErrorLogPath -Leaf
    $ProcessErrorLogDestination = "{0}\\{1}" -f
        $BertaResultProcessPath,
        $ProcessErrorLogName
    if (Test-Path -Path $ProcessErrorLogDestination) {
        Remove-Item -Path $ProcessErrorLogDestination -Force | out-null
    }

    Win-DebugTimestamp -output (
        "{0}: Move output log from '{1}' to '{2}'" -f
            $keyWords,
            $ProcessOutputLogPath,
            $ProcessOutputLogDestination
    )
    Win-DebugTimestamp -output (
        "{0}: Move error log from '{1}' to '{2}'" -f
            $keyWords,
            $ProcessErrorLogPath,
            $ProcessErrorLogDestination
    )

    if ($Remote) {
        if (Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessOutputLogPath)
                Test-Path -Path $ProcessOutputLogPath
            } -ArgumentList $ProcessOutputLogPath) {
            Copy-Item `
                -FromSession $Session `
                -Path $ProcessOutputLogPath `
                -Destination $ProcessOutputLogDestination `
                -Force `
                -Confirm:$false | out-null

            Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessOutputLogPath)
                Remove-Item -Path $ProcessOutputLogPath -Force | out-null
            } -ArgumentList $ProcessOutputLogPath
        }

        if (Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessErrorLogPath)
                Test-Path -Path $ProcessErrorLogPath
            } -ArgumentList $ProcessErrorLogPath) {
            Copy-Item `
                -FromSession $Session `
                -Path $ProcessErrorLogPath `
                -Destination $ProcessErrorLogDestination `
                -Force `
                -Confirm:$false | out-null

            Invoke-Command -Session $Session -ScriptBlock {
                Param($ProcessErrorLogPath)
                Remove-Item -Path $ProcessErrorLogPath -Force | out-null
            } -ArgumentList $ProcessErrorLogPath
        }
    } else {
        if (Test-Path -Path $ProcessOutputLogPath) {
            Copy-Item `
                -Path $ProcessOutputLogPath `
                -Destination $ProcessOutputLogDestination `
                -Force `
                -Confirm:$false | out-null
            Remove-Item -Path $ProcessOutputLogPath -Force | out-null
        }

        if (Test-Path -Path $ProcessErrorLogPath) {
            Copy-Item `
                -Path $ProcessErrorLogPath `
                -Destination $ProcessErrorLogDestination `
                -Force `
                -Confirm:$false | out-null
            Remove-Item -Path $ProcessErrorLogPath -Force | out-null
        }
    }

    if ($ReturnValue.result) {
        Win-DebugTimestamp -output (
            "The process({0}) ---------------------- passed" -f $keyWords
        )
    } else {
        Win-DebugTimestamp -output (
            "The process({0}) ---------------------- failed > {1}" -f $keyWords, $ReturnValue.error
        )
    }

    return $ReturnValue
}

function Gtest-CollectTestResult
{
    Param(
        [Parameter(Mandatory=$True)]
        [array]$TestCaseArray,

        [array]$BaseArray = [System.Array] @()
    )

    #$TestCaseTemplate = [hashtable] @{
    #    name = $null
    #    result = $null
    #    error = "no_error"
    #}

    $ReturnValue = [System.Array] @()

    if ($BaseArray.Length -eq 0) {
        $ReturnValue = $TestCaseArray
    } else {
        $ReturnValue = $BaseArray
        Foreach ($TestCase in $TestCaseArray) {
            $TestExist = $false
            Foreach ($BaseTestCase in $BaseArray) {
                if ($BaseTestCase.name -eq $TestCase.name) {
                    $TestExist = $true
                    if ($BaseTestCase.result -ne $TestCase.result) {
                        if ($TestCase.result) {
                            $TestCase.result = $BaseTestCase.result
                            $TestCase.error = $BaseTestCase.error
                        }
                    }
                }
            }

            if (-not $TestExist) {$ReturnValue += $TestCase}
        }
    }

    return $ReturnValue
}

# About process runner
function Gtest-Process
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [Parameter(Mandatory=$True)]
        [bool]$ListFlag,

        [Parameter(Mandatory=$True)]
        [string]$keyWords,

        [string]$VMNameSuffix = $null
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testcases = [System.Array] @()
    }

    Start-Sleep -Seconds 5

    WBase-GetInfoFile | out-null

    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    if ($Remote) {
        $LogKeyWord = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
        $PSSessionName = "Session_{0}" -f $VMNameSuffix
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true `
            -CheckFlag $false
    } else {
        $LogKeyWord = "Host"
    }

    Win-DebugTimestamp -output (
        "{0}: Start Gtest({1}) process ..." -f $LogKeyWord, $TestType
    )

    $ProcessList = [hashtable] @{}
    $GtestArgsArray = [System.Array] @()
    $GTtstResultName = "ProcessResult_{0}.json" -f $keyWords
    $GtestResultPath = "{0}\\{1}" -f $LocalProcessPath, $GTtstResultName

    if ($TestType -eq "compress_multi_process") {
        $ProcessName = "qatzip_gtest"
        $GtestArgsArray += "QzPositiveFullCompress*Deflate4B"
        $GtestArgsArray += "QzPositiveFullCompress*DeflateGzipExt"
    } elseif ($TestType -eq "compress_positive") {
        $ProcessName = "qatzip_gtest"
        $GtestArgsArray += "Qz*Positive"
    } elseif ($TestType -eq "compress_negative") {
        $ProcessName = "qatzip_gtest"
        $GtestArgsArray += "Qz*Negative"
    }

    if ($Remote) {
        $ProcessFilePath = "{0}\{1}.exe" -f $STVWinPath, $ProcessName
    } else {
        $ProcessFilePath = "{0}\{1}.exe" -f $Gtest.GtestPath, $ProcessName
    }

    # Start Gtest as process with different arg
    Foreach ($GtestArgs in $GtestArgsArray) {
        $ProcessArgs = "--gtest_filter=*{0}*" -f $GtestArgs
        if ($ListFlag) {
            $ProcessArgs = "{0} --gtest_list_tests" -f $ProcessArgs
        }
        $keyWordsTmp = $GtestArgs.split("*")[1]
        $keyWordsTmp = $keyWordsTmp.split(":-")[0]
        if ($Remote) {
            $ProcessKeyWords = "Gtest_{0}_{1}" -f $keyWordsTmp, $VMNameSuffix

            $GtestProcess = WBase-StartProcess `
                -ProcessFilePath $ProcessFilePath `
                -ProcessArgs $ProcessArgs `
                -keyWords $ProcessKeyWords `
                -Remote $Remote `
                -Session $Session
        } else {
            $ProcessKeyWords = "Gtest_{0}_Host" -f $keyWordsTmp

            $GtestProcess = WBase-StartProcess `
                -ProcessFilePath $ProcessFilePath `
                -ProcessArgs $ProcessArgs `
                -keyWords $ProcessKeyWords `
                -Remote $Remote
        }

        $ProcessList[$ProcessKeyWords] = [hashtable] @{
            Output = $GtestProcess.Output
            Error = $GtestProcess.Error
            Result = $GtestProcess.Result
        }
    }

    # Wait all Gtest process to complete
    if ($Remote) {
        $WaitStatus = WBase-WaitProcessToCompletedByName `
            -ProcessName $ProcessName `
            -Remote $Remote `
            -Session $Session
    } else {
        $WaitStatus = WBase-WaitProcessToCompletedByName `
            -ProcessName $ProcessName `
            -Remote $Remote
    }

    if (-not $WaitStatus.result) {
        $ReturnValue.result = $WaitStatus.result
        $ReturnValue.error = $WaitStatus.error
    }

    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $GtestResultPath | out-null

    Win-DebugTimestamp -output (
        "{0}: Check the result of Gtest({1}) process ..." -f $LogKeyWord, $TestType
    )

    # Check Gtest output log
    Foreach ($GtestArgs in $GtestArgsArray) {
        $keyWordsTmp = $GtestArgs.split("*")[1]
        $keyWordsTmp = $keyWordsTmp.split(":-")[0]
        if ($Remote) {
            $ProcessKeyWords = "Gtest_{0}_{1}" -f $keyWordsTmp, $VMNameSuffix

            $GtestProcessResult = Gtest-CheckProcessOutput `
                -ProcessOutputLogPath $ProcessList[$ProcessKeyWords].Output `
                -ProcessErrorLogPath $ProcessList[$ProcessKeyWords].Error `
                -keyWords $ProcessKeyWords `
                -Remote $Remote `
                -Session $Session
        } else {
            $ProcessKeyWords = "Gtest_{0}_Host" -f $keyWordsTmp

            $GtestProcessResult = Gtest-CheckProcessOutput `
                -ProcessOutputLogPath $ProcessList[$ProcessKeyWords].Output `
                -ProcessErrorLogPath $ProcessList[$ProcessKeyWords].Error `
                -keyWords $ProcessKeyWords `
                -Remote $Remote
        }

        if ($GtestProcessResult.testcases.length -ne 0) {
            if ($ReturnValue.testcases.Length -eq 0) {
                $ReturnValue.testcases = Gtest-CollectTestResult `
                    -TestCaseArray $GtestProcessResult.testcases
            } else {
                $ReturnValue.testcases = Gtest-CollectTestResult `
                    -TestCaseArray $GtestProcessResult.testcases `
                    -BaseArray $ReturnValue.testcases
            }
        }
    }

    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $GtestResultPath | out-null
}

function Gtest-Entry
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [Parameter(Mandatory=$True)]
        [string]$TestType,

        [bool]$ListFlag = $false
    )

    $ReturnValue = [hashtable] @{
        result = $true
        error = "no_error"
        testcases = [System.Array] @()
    }

    WBase-GenerateInfoFile | out-null

    $ProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()
    $GtestArgsArray = [System.Array] @()
    $PlatformList = [System.Array] @()
    if ($Remote) {
        $PlatformList = $LocationInfo.VM.NameArray
    } else {
        $PlatformList += "Host"
    }

    # Run Gtest as process
    $PlatformList | ForEach-Object {
        $GtestProcessArgs = "Gtest-Process -TestType {0}" -f $TestType
        if ($Remote) {
            $GtestProcessArgs = "{0} -Remote 1" -f $GtestProcessArgs
            $GtestProcessArgs = "{0} -VMNameSuffix {1}" -f $GtestProcessArgs, $_
        } else {
            $GtestProcessArgs = "{0} -Remote 0" -f $GtestProcessArgs
        }
        $GtestProcessKeyWords = "gtest_{0}" -f $_
        $GtestProcessArgs = "{0} -keyWords {1}" -f $GtestProcessArgs, $GtestProcessKeyWords
        if ($ListFlag) {
            $GtestProcessArgs = "{0} -ListFlag 1" -f $GtestProcessArgs
        } else {
            $GtestProcessArgs = "{0} -ListFlag 0" -f $GtestProcessArgs
        }

        $GtestProcess = WBase-StartProcess `
            -ProcessFilePath "pwsh" `
            -ProcessArgs $GtestProcessArgs `
            -keyWords $GtestProcessKeyWords `
            -Remote $false

        $ProcessList[$_] = [hashtable] @{
            Output = $GtestProcess.Output
            Error = $GtestProcess.Error
            Result = $GtestProcess.Result
        }

        $ProcessIDArray += $GtestProcess.ID
    }

    # Wait for parcomp process
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null

    # Check output and error log for gtest process
    $PlatformList | ForEach-Object {
        $GtestProcessKeyWords = "gtest_{0}" -f $_

        $GtestResult = WBase-CheckProcessOutput `
            -ProcessOutputLogPath $ProcessList[$_].Output `
            -ProcessErrorLogPath $ProcessList[$_].Error `
            -ProcessResultPath $ProcessList[$_].Result `
            -Remote $false `
            -keyWords $GtestProcessKeyWords

        if ($ReturnValue.result) {
            $ReturnValue.result = $GtestResult.result
            $ReturnValue.error = $GtestResult.error
        }

        if ($GtestResult.testResult.testcases.length -eq 0) {
            if ($ReturnValue.result) {
                $ReturnValue.result = $false
                $ReturnValue.error = "no_test_{0}" -f $_
            }
        } else {
            if ($ReturnValue.testcases.Length -eq 0) {
                $ReturnValue.testcases = Gtest-CollectTestResult `
                    -TestCaseArray $GtestResult.testResult.testcases
            } else {
                $ReturnValue.testcases = Gtest-CollectTestResult `
                    -TestCaseArray $GtestResult.testResult.testcases `
                    -BaseArray $ReturnValue.testcases
            }
        }
    }

    return $ReturnValue
}


Export-ModuleMember -Variable *-*
Export-ModuleMember -Function *-*
