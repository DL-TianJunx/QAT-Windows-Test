Param(
    [Parameter(Mandatory = $True)]
    [string]$app_path,

    [Parameter(Mandatory = $True)]
    [string]$samples_path,

    [Parameter(Mandatory = $True)]
    [string]$samples_result_path
)

function UT-checkServicesData {
    Param(
        [Parameter(Mandatory = $True)]
        [string]$CheckServiceEnableFlag,

        [Parameter(Mandatory = $True)]
        [string]$CheckServiceNeededFlag,

        [Parameter(Mandatory = $True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $true

    if ($Remote) {
        $LogKeyWord = $Session.Name
    }
    else {
        $LogKeyWord = "Host"
    }

    Win-DebugTimestamp -output (
        "{0}: Check ServicesEnable as {1}, ServicesNeeded as {2}" -f $LogKeyWord, $CheckServiceEnableFlag, $CheckServiceNeededFlag
    )

    $regeditKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_4940&SUBSYS_00008086&REV_40\3&1fc35236&0&00\Device Parameters\General"
    $GetFlag = $false

    # Check: exist
    if ($Remote) {
        $GetFlag = Invoke-Command -Session $Session -ScriptBlock {
            Param($regeditKey)
            if (Test-Path -Path $regeditKey) {
                return $true
            }
            else {
                return $false
            }
        } -ArgumentList $regeditKey
    }
    else {
        if (Test-Path -Path $regeditKey) {
            $GetFlag = $true
        }
        else {
            $GetFlag = $false
        }
    }
    # Get Services Data and compare
    if ($GetFlag) {
        if ($Remote) {
            $ServicesEnableInfo = Invoke-Command -Session $Session -ScriptBlock {
                Param($regeditKey)
                return (Get-ItemProperty $regeditKey).ServicesEnabled
            } -ArgumentList $regeditKey
            $ServicesNeededInfo = Invoke-Command -Session $Session -ScriptBlock {
                Param($regeditKey)
                return (Get-ItemProperty $regeditKey).ServicesNeeded
            } -ArgumentList $regeditKey
        }
        else {
            $ServicesEnableInfo = (Get-ItemProperty -Path $regeditKey).ServicesEnabled
            $ServicesNeededInfo = (Get-ItemProperty -Path $regeditKey).ServicesNeeded
        }

        if (($ServicesEnableInfo -eq "sym") -and ($ServicesNeededInfo -eq "sym")) {
            $ReturnValue = $true
        }
        else {
            $ReturnValue = $false
        }
    }
    else {
        # The regedit key is null, return true and not changed
        $ReturnValue = $true
    }
    return $ReturnValue
}     

function UT-SetServicesData {
    Param(
        [Parameter(Mandatory = $True)]
        [string]$ServiceEnable,

        [Parameter(Mandatory = $True)]
        [string]$ServiceNeeded,

        [Parameter(Mandatory = $True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $true

    $regeditKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_4940&SUBSYS_00008086&REV_40\3&1fc35236&0&00\Device Parameters\General"
    # if ($UQMode) {
    #     $SetUQValue = 1
    # } else {
    #     $SetUQValue = 0
    # }

    $SetFlag = $false

    # Check: exist
    if ($Remote) {
        $LogKeyWord = $Session.Name
        $SetFlag = Invoke-Command -Session $Session -ScriptBlock {
            Param($regeditKey)
            if (Test-Path -Path $regeditKey) {
                return $true
            }
            else {
                return $false
            }
        } -ArgumentList $regeditKey
    }
    else {
        $LogKeyWord = "Host"
        if (Test-Path -Path $regeditKey) {
            $SetFlag = $true
        }
        else {
            $SetFlag = $false
        }
    }

    # Set Services Data
    if ($SetFlag) {
        Win-DebugTimestamp -output (
            "{0}: Set ServicesEnable as {1}, ServicesNeeded as {2}, need to restart PC" -f
            $LogKeyWord,
            $ServiceEnable,
            $ServiceNeeded
        )

        if ($Remote) {
            Invoke-Command -Session $Session -ScriptBlock {
                Param($regeditKey, $ServiceEnable)
                Set-ItemProperty $regeditKey -Name "ServicesEnabled" -Value $ServiceEnable
            } -ArgumentList $regeditKey, $ServiceEnable | out-null

            Invoke-Command -Session $Session -ScriptBlock {
                Param($regeditKey, $ServiceNeeded)
                Set-ItemProperty $regeditKey -Name "ServicesNeeded" -Value $ServiceNeeded
            } -ArgumentList $regeditKey, $ServiceNeeded | out-null

            $ReturnValue = UT-checkServicesData -CheckServiceEnableFlag "sym" -CheckServiceNeededFlag "sym" -Session $Session -Remote $Remote
        }
        else {
            Set-ItemProperty $regeditKey -Name "ServicesEnabled" -Value $ServiceEnable | out-null
            Set-ItemProperty $regeditKey -Name "ServicesNeeded" -Value $ServiceNeeded | out-null
            $ReturnValue = UT-checkServicesData -CheckServiceEnableFlag "sym" -CheckServiceNeededFlag "sym" -Remote $Remote
        }
    }
    else {
        Win-DebugTimestamp -output ("{0}: The Services key is not exist, no need to set" -f $LogKeyWord)
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Set ServicesEnable as {1}, ServicesNeeded as {2} is successful" -f $LogKeyWord, $ServiceEnable, $ServiceNeeded
        )
    }
    else {
        Win-DebugTimestamp -output (
            "{0}: Set ServicesEnable as {1}, ServicesNeeded as {2} is unsuccessful" -f $LogKeyWord, $ServiceEnable, $ServiceNeeded
        )
    }

    return $ReturnValue
}

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
UT-WorkAround `
    -Remote $false `
    -DisableFlag $DisableDeviceFlag | out-null

# Check and set Services Data
$ServicesStatus = UT-checkServicesData `
    -CheckServiceEnableFlag "sym" `
    -CheckServiceNeededFlag "sym" `
    -Remote $false
if (-not $ServicesStatus) {
    UT-SetServicesData `
        -ServiceEnable "sym" `
        -ServiceNeeded "sym" `
        -Remote $false | out-null
}
# Enable regedit or restart PC
# Stop-Service -Name spooler
# Start-Service -Name spooler

Write-Output "app_path: $app_path"
Write-Output "samples_path: $samples_path"
Write-Output "samples_result_path: $samples_result_path"

$batch = Get-Content -Path $samples_path | ConvertFrom-Json

$currentDir = Get-Location
$app_in_file = Join-Path -Path $currentDir -ChildPath "in.hex"
$app_key_file = Join-Path -Path $currentDir -ChildPath "key.hex"
$app_iv_file = Join-Path -Path $currentDir -ChildPath "iv.hex"
$app_aad_file = Join-Path -Path $currentDir -ChildPath "aad.hex"
$app_out_file = Join-Path -Path $currentDir -ChildPath "out.hex"

# Init input file and create them
$emptyBytes = @()
$emptyBytes | Out-File $app_in_file -Force -Encoding utf8
$emptyBytes | Out-File $app_key_file -Force -Encoding utf8
$emptyBytes | Out-File $app_iv_file -Force -Encoding utf8
$emptyBytes | Out-File $app_aad_file -Force -Encoding utf8

$pt_encrypt_file = Join-Path -Path $currentDir -ChildPath "pt_encrypt.hex"
$pt_decrypt_file = Join-Path -Path $currentDir -ChildPath "pt_decrypt.hex"
$pt_encrypt_random_file = Join-Path -Path $currentDir -ChildPath "pt_encrypt_random.hex"
$pt_decrypt_random_file = Join-Path -Path $currentDir -ChildPath "pt_decrypt_random.hex"

function Execute_exe {
    param (
        [Parameter(Mandatory = $True)]
        [string]$direction,

        [string]$in_file,

        [string]$key_file,

        [string]$iv_file,

        [string]$aad_file,

        [Parameter(Mandatory = $True)]
        [string]$tagLen,

        [Parameter(Mandatory = $True)]
        [string]$payloadLen
    )

    if (-not ($in_file -eq '') ) {
        $in_file | Out-File $app_in_file -Encoding ascii
    }
    
    if (-not ($key_file -eq '') ) {
        $key_file | Out-File -FilePath $app_key_file -Force -Encoding utf8
    }
    
    if (-not ($iv_file -eq '') ) {
        if ("ACVP-AES-ECB" -eq $batch.algorithm) {
            "00000000000000000000000000000000" | Out-File -FilePath $app_iv_file -Force -Encoding utf8
        }
        else {
            $iv_file | Out-File -FilePath $app_iv_file -Force -Encoding utf8
        }
    }
    
    if (-not ($aad_file -eq '') ) {
        $aad_file | Out-File -FilePath $app_aad_file -Force -Encoding utf8
    }

    $arguments = "$direction $app_in_file $app_key_file $app_iv_file $app_aad_file $tagLen $payloadLen $app_out_file"
    Try {
        Start-Process -FilePath $app_path -ArgumentList $arguments -Wait -NoNewWindow
    }
    Catch {
        Write-Output $_.Exception.Message
    }
}

function compare_MD5 {
    param (
        [Parameter(Mandatory = $True)]
        [string]$pt_before,

        [Parameter(Mandatory = $True)]
        [string]$pt_after
    )
    $ReturnValue = $false
    $pt_encryptHash = certutil -hashfile $pt_before MD5
    $pt_decryptHash = certutil -hashfile $pt_after MD5
    if ($pt_encryptHash[1] -eq $pt_decryptHash[1]) {
        $ReturnValue = $true
    }
    else {
        $ReturnValue = $false
    }
    return $ReturnValue
}

$result_obj = @()
$batchResult = @{}
$batchResult["vsId"] = $batch.vsId
$batchResult["algorithm"] = $batch.algorithm
$batchResult["revision"] = $batch.revision
$batchResult["isSample"] = $batch.isSample
$batchResult["testGroups"] = @()

foreach ($test_group in $batch.testGroups) {
    Write-Output "Started test group $($test_group.tgId)"
    $test_group_results = @{}

    $test_group_results["tgId"] = $test_group.tgId
    $test_group_results["tests"] = @()

    if ($test_group.testType -eq "AFT") {
        foreach ($test in $test_group.tests) {
            Write-Output "`t started test $($test.tcId)"
            $testResult = @{}
            $testResult["tcId"] = $test.tcId

            #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            # beginning of alg dependend section
            #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

            if ($test_group.direction -eq "encrypt") {
                $test.pt | Out-File -FilePath $app_in_file -Force -Encoding utf8
                $test.pt | Out-File -FilePath $pt_encrypt_file -Force -Encoding utf8
            }
            else {
                $random_pt = -join (1..($test_group.payloadLen / 4) | % { [char][int]((48..57 + 65..70) | Get-Random) })
                $random_pt | Out-File $pt_encrypt_random_file -Encoding ascii

                Execute_exe `
                    -direction `"encrypt`" `
                    -in_file $random_pt `
                    -key_file $test.key `
                    -iv_file $test.iv `
                    -aad_file $test.aad `
                    -tagLen `"$($test_group.tagLen)`" `
                    -payloadLen `"$($test_group.payloadLen)`"
                
                $random_Response = Get-Content $app_out_file
                $random_Response | Out-File -FilePath $app_in_file -Force -Encoding utf8
            }

            Execute_exe `
                -direction `"$($test_group.direction)`" `
                -key_file $test.key `
                -iv_file $test.iv `
                -aad_file $test.aad `
                -tagLen `"$($test_group.tagLen)`" `
                -payloadLen `"$($test_group.payloadLen)`"

            #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            # end of alg dependent section
            #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

            $appResponse = Get-Content $app_out_file
            $splitValue = [int]($test_group.tagLen / 4)
            if ($test_group.direction -eq "encrypt") {
                $outFileSize = (Get-Item $app_out_file).length
                if ($outFileSize -eq 0) {
                    $testResult["test encrypt"] = "encrypt Failed"
                    Write-Output "`t test $($test.tcId) encrypt Failed!"
                }
                else {
                    $testResult["ct"] = $appResponse.Substring(0, $appResponse.Length - $splitValue)
                    $testResult["tag"] = $appResponse.Substring($appResponse.Length - $splitValue)
    
                    #Compare the MD5 values of plaintext before encryption and plaintext after decryption
                    Execute_exe `
                        -direction `"decrypt`" `
                        -in_file ($testResult["ct"] + $testResult["tag"]) `
                        -tagLen `"$($test_group.tagLen)`" `
                        -payloadLen `"$($test_group.payloadLen)`"
                    
                    $appResponse = Get-Content $app_out_file
                    $outFileSize = (Get-Item $app_out_file).length
                    $splitValue = [int]($test_group.tagLen / 4)
                    if ($outFileSize -eq 0) {
                        $testResult["test decrypt"] = "decrypt Failed"
                        Write-Output "`t test $($test.tcId) decrypt Failed!"
                    }
                    else {
                        $testResult["pt"] = $appResponse.Substring(0)
                        $testResult["pt"] | Out-File -FilePath $pt_decrypt_file -Force -Encoding utf8
                        
                        $compareValue = compare_MD5 -pt_before $pt_encrypt_file -pt_after $pt_decrypt_file  
                        if ($compareValue) {
                            $testResult["testCase"] = "Passed"
                            Write-Output "`t test $($test.tcId) Passed!"
                        }
                        else {
                            $testResult["testCase"] = "Failed"
                            Write-Output "`t test $($test.tcId) Failed!"
                        }
                    }
                }
            }
            else {
                $outFileSize = (Get-Item $app_out_file).length
                if ($outFileSize -eq 0) {
                    $testResult["test decrypt"] = "decrypt Failed"
                    Write-Output "`t test $($test.tcId) decrypt Failed!"
                }
                else {
                    $testResult["pt"] = $appResponse.Substring(0)
                    $testResult["pt"] | Out-File -FilePath $pt_decrypt_random_file -Force -Encoding utf8

                    $compareValue = compare_MD5 -pt_before $pt_encrypt_random_file -pt_after $pt_decrypt_random_file  
                    if ($compareValue) {
                        $testResult["testCase"] = "Passed"
                        Write-Output "`t test $($test.tcId) Passed!"
                    }
                    else {
                        $testResult["testCase"] = "Failed"
                        Write-Output "`t test $($test.tcId) Failed!"
                    }
                }
            }

            $test_group_results["tests"] += $testResult
            Write-Output "`t End test $($test.tcId)"
        }
        $batchResult["testGroups"] += $test_group_results
        Write-Output "End test group $($test_group.tgId)"
    }
}
$result_obj += $batchResult
$result_obj | ConvertTo-Json -Depth 100 | Out-File -FilePath $samples_result_path -Encoding utf8



