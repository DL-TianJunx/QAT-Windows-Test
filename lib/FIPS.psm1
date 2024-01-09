$FIPSPath = "{0}\FIPS" -f $QATTESTPATH
$samples_path = "{0}\ACVP-AES-GCM.req" -f $FIPSPath
$global:FIPS = [hashtable] @{
    SourcePath   = "\\10.67.115.211\mountBertaCTL\FIPS"
    batch        = Get-Content -Path $samples_path | ConvertFrom-Json
    app_in_file  = Join-Path -Path $FIPSPath -ChildPath "in.hex"
    app_key_file = Join-Path -Path $FIPSPath -ChildPath "key.hex"
    app_iv_file  = Join-Path -Path $FIPSPath -ChildPath "iv.hex"
    app_aad_file = Join-Path -Path $FIPSPath -ChildPath "aad.hex"
    app_out_file = Join-Path -Path $FIPSPath -ChildPath "out.hex"
}

# About process runner
function FIPS-Process {
    Param(
        [Parameter(Mandatory = $True)]
        [string]$tgId,

        [Parameter(Mandatory = $True)]
        [string]$tcId,

        [Parameter(Mandatory = $True)]
        [string]$direction,
    
        [string]$in,
    
        [string]$key,
    
        [string]$iv_,
    
        [string]$aad,

        [Parameter(Mandatory = $True)]
        [string]$aadLen,
    
        [Parameter(Mandatory = $True)]
        [string]$tagLen,
    
        [Parameter(Mandatory = $True)]
        [string]$payloadLen,

        [Parameter(Mandatory = $True)]
        [string]$keyWords,

        [Parameter(Mandatory = $True)]
        [bool]$Remote,

        [string]$VMNameSuffix = $null
    )

    $ReturnValue = [hashtable] @{
        result    = $true
        error     = "no_error"
        testcases = [System.Array] @()
    }

    Start-Sleep -Seconds 5

    WBase-GetInfoFile | out-null

    $LocationInfo.WriteLogToConsole = $true
    $LocationInfo.WriteLogToFile = $false

    if ([String]::IsNullOrEmpty($WinTestProcessPath)) {
        $WinTestProcessPath = "{0}\\Process" -f $LocationInfo.BertaResultPath
    }

    if ([String]::IsNullOrEmpty($LocationInfo.TestCaseName)) {
        $FIPSResultPath = "{0}\\{1}_Result.json" -f
        $WinTestProcessPath,
        $keyWords
    }
    else {
        $FIPSResultPath = "{0}\\{1}_{2}_Result.json" -f
        $WinTestProcessPath,
        $keyWords,
        $LocationInfo.TestCaseName
    }

    if ($Remote) {
        $LogKeyWord = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
        $PSSessionName = "Session_{0}" -f $VMNameSuffix
        $vmName = "{0}_{1}" -f $env:COMPUTERNAME, $VMNameSuffix
        $Session = HV-PSSessionCreate `
            -VMName $vmName `
            -PSName $PSSessionName `
            -IsWin $true `
            -CheckFlag $false
    }
    else {
        $LogKeyWord = "Host"
    }

    Win-DebugTimestamp -output (
        "{0}: Start FIPS process ..." -f $LogKeyWord
    )

    # Init input file and create them
    $emptyBytes = @()
    $emptyBytes | Out-File $FIPS.app_in_file -Force -Encoding utf8
    $emptyBytes | Out-File $FIPS.app_key_file -Force -Encoding utf8
    $emptyBytes | Out-File $FIPS.app_iv_file -Force -Encoding utf8
    $emptyBytes | Out-File $FIPS.app_aad_file -Force -Encoding utf8

    $pt_encrypt_file = Join-Path -Path $FIPSPath -ChildPath "pt_encrypt.hex"
    $pt_decrypt_file = Join-Path -Path $FIPSPath -ChildPath "pt_decrypt.hex"
    $pt_encrypt_random_file = Join-Path -Path $FIPSPath -ChildPath "pt_encrypt_random.hex"
    $pt_decrypt_random_file = Join-Path -Path $FIPSPath -ChildPath "pt_decrypt_random.hex"

    $ProcessName = "fips_windows"

    if ($Remote) {
        $ProcessFilePath = "{0}\{1}.exe" -f $STVWinPath, $ProcessName
    }
    else {
        $ProcessFilePath = "{0}\{1}.exe" -f $FIPSPath, $ProcessName
    }
    
    #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # beginning of alg dependend section
    #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    if ($direction -eq "encrypt") {
        if($payloadLen -eq 0){
            $in = ""
        }
        $in | Out-File -FilePath $FIPS.app_in_file -Force -Encoding utf8
        $in | Out-File -FilePath $pt_encrypt_file -Force -Encoding utf8
    }
    else {
        if ($payloadLen -eq 0) {
            $random_pt = ""
        }
        else {
            $random_pt = -join (1..($payloadLen / 4) | % { [char][int]((48..57 + 65..70) | Get-Random) })
        }
        if($aadLen -eq 0){
            $aad = ""
        }
        $random_pt | Out-File $pt_encrypt_random_file -Encoding ascii
    
        if ($Remote) {
            $ProcessKeyWords = "FIPS_{0}_tgId {1}_pt to encrypt_tcId {2}" -f , $VMNameSuffix, $($tgId), $($tcId)

            $inProcess = FIPStest `
                -ProcessKeyWords $ProcessKeyWords `
                -ProcessFilePath $ProcessFilePath `
                -direction `"encrypt`" `
                -in_file $random_pt `
                -key_file $key `
                -iv_file $iv_ `
                -aad_file $aad `
                -tagLen `"$($tagLen)`" `
                -payloadLen `"$($payloadLen)`" `
                -Remote $Remote `
                -Session $Session
        }
        else {
            $ProcessKeyWords = "FIPS_tgId {0}_pt to encrypt_tcId {1}" -f $($tgId), $($tcId)
            $inProcess = FIPStest `
                -ProcessKeyWords $ProcessKeyWords `
                -ProcessFilePath $ProcessFilePath `
                -direction `"encrypt`" `
                -in_file $random_pt `
                -key_file $key `
                -iv_file $iv_ `
                -aad_file $aad `
                -tagLen `"$($tagLen)`" `
                -payloadLen `"$($payloadLen)`" `
                -Remote $Remote
        }
                    
        if ($Remote) {
            $WaitStatus = WBase-WaitProcessToCompletedByID `
                -ProcessID $inProcess.process.ID `
                -Remote $Remote `
                -Session $Session
        }
        else {
            $WaitStatus = WBase-WaitProcessToCompletedByID `
                -ProcessID $inProcess.process.ID `
                -Remote $Remote
        }
                
        if (-not $WaitStatus.result) {
            $ReturnValue.result = $WaitStatus.result
            $ReturnValue.error = $WaitStatus.error
        }
    
        # Start-Sleep -Seconds 3
    
        # Double check the output log
        if ($ReturnValue.result) {
            $CheckOutput = WBase-CheckOutputLog `
                -TestOutputLog $inProcess.process.Output `
                -TestErrorLog $inProcess.process.Error `
                -checkFIPSLog $true `
                -Remote $Remote
    
            $ReturnValue.result = $CheckOutput.result
            $ReturnValue.error = $CheckOutput.error
        }
    
        WBase-WriteHashtableToJsonFile `
            -Info $ReturnValue `
            -InfoFilePath $FIPSResultPath | out-null

        $random_Response = Get-Content $FIPS.app_out_file
        $random_Response | Out-File -FilePath $FIPS.app_in_file -Force -Encoding utf8
    }
    if ($Remote) {
        if($aadLen -eq 0){
            $aad = ""
        }
        $ProcessKeyWords = "FIPS_{0}_tgId {1}_{2}_tcId {3}" -f , $VMNameSuffix, $($tgId), $($direction), $($tcId)
        $inProcess = FIPStest `
            -ProcessKeyWords $ProcessKeyWords `
            -ProcessFilePath $ProcessFilePath `
            -direction `"$($direction)`" `
            -key_file $key `
            -iv_file $iv_ `
            -aad_file $aad `
            -tagLen `"$($tagLen)`" `
            -payloadLen `"$($payloadLen)`" `
            -Remote $Remote `
            -Session $Session
    }
    else {
        if($aadLen -eq 0){
            $aad = ""
        }
        $ProcessKeyWords = "FIPS_tgId {0}_{1}_tcId {2}" -f $($tgId), $($direction), $($tcId)
        $inProcess = FIPStest `
            -ProcessKeyWords $ProcessKeyWords `
            -ProcessFilePath $ProcessFilePath `
            -direction `"$($direction)`" `
            -key_file $key `
            -iv_file $iv_ `
            -aad_file $aad `
            -tagLen `"$($tagLen)`" `
            -payloadLen `"$($payloadLen)`" `
            -Remote $Remote
    }

    if ($Remote) {
        $WaitStatus = WBase-WaitProcessToCompletedByID `
            -ProcessID $inProcess.process.ID `
            -Remote $Remote `
            -Session $Session
    }
    else {
        $WaitStatus = WBase-WaitProcessToCompletedByID `
            -ProcessID $inProcess.process.ID `
            -Remote $Remote
    }
            
    if (-not $WaitStatus.result) {
        $ReturnValue.result = $WaitStatus.result
        $ReturnValue.error = $WaitStatus.error
    }

    # Double check the output log
    if ($ReturnValue.result) {
        $CheckOutput = WBase-CheckOutputLog `
            -TestOutputLog $inProcess.process.Output `
            -TestErrorLog $inProcess.process.Error `
            -checkFIPSLog $true `
            -Remote $Remote

        $ReturnValue.result = $CheckOutput.result
        $ReturnValue.error = $CheckOutput.error
    }

    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $FIPSResultPath | out-null

    Win-DebugTimestamp -output (
        "{0}: Check the result of FIPS {1} process ..." -f $LogKeyWord, $ProcessKeyWords
    )

    #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # end of alg dependent section
    #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    $appResponse = Get-Content $FIPS.app_out_file
    $outputResponse = Get-Content $inProcess.process.Output
    $splitValue = [int]($tagLen / 4)
    if ($direction -eq "encrypt") {
        if ($outputResponse -match "SymmEncrypt failed") {
            # $test_results["test encrypt"] = "encrypt Failed"
            $ReturnValue.result = $false
            Win-DebugTimestamp -output ( "`t test $($tcId) encrypt Failed!" )
        }
        else {
            $ct = $appResponse.Substring(0, $appResponse.Length - $splitValue)
            $tag = $appResponse.Substring($appResponse.Length - $splitValue)
        
            #Compare the MD5 values of plaintext before encryption and plaintext after decryption
            $outProcessKeyWords = "FIPS_tgId {0}_pt to decrypt_tcId {1}" -f $($tgId), $($tcId)
            if ($Remote) {
                $outProcess = FIPStest `
                    -ProcessKeyWords $outProcessKeyWords `
                    -ProcessFilePath $ProcessFilePath `
                    -direction `"decrypt`" `
                    -in_file ($ct + $tag) `
                    -tagLen `"$($tagLen)`" `
                    -payloadLen `"$($payloadLen)`" `
                    -Remote $Remote `
                    -Session $Session
            }
            else {
                $outProcess = FIPStest `
                    -ProcessKeyWords $outProcessKeyWords `
                    -ProcessFilePath $ProcessFilePath `
                    -direction `"decrypt`" `
                    -in_file ($ct + $tag) `
                    -tagLen `"$($tagLen)`" `
                    -payloadLen `"$($payloadLen)`" `
                    -Remote $Remote
            }
            if ($Remote) {
                $WaitStatus = WBase-WaitProcessToCompletedByID `
                    -ProcessID $outProcess.process.ID `
                    -Remote $Remote `
                    -Session $Session
            }
            else {
                $WaitStatus = WBase-WaitProcessToCompletedByID `
                    -ProcessID $outProcess.process.ID `
                    -Remote $Remote
            }

            if (-not $WaitStatus.result) {
                $ReturnValue.result = $WaitStatus.result
                $ReturnValue.error = $WaitStatus.error
            }

            # Double check the output log
            if ($ReturnValue.result) {
                $CheckOutput = WBase-CheckOutputLog `
                    -TestOutputLog $outProcess.process.output `
                    -TestErrorLog $outProcess.process.Error `
                    -checkFIPSLog $true `
                    -Remote $Remote

                $ReturnValue.result = $CheckOutput.result
                $ReturnValue.error = $CheckOutput.error
            }

            WBase-WriteHashtableToJsonFile `
                -Info $ReturnValue `
                -InfoFilePath $FIPSResultPath | out-null

            $appResponse = Get-Content $FIPS.app_out_file
            $outputResponse = Get-Content $outProcess.process.Output
            $splitValue = [int]($tagLen / 4)
            if ($outputResponse -match "decrypt failed") {
                # $test_results["test decrypt"] = "decrypt Failed"
                $ReturnValue.result = $false
                Win-DebugTimestamp -output ( "`t test $($tcId) decrypt Failed!")
            }
            else {
                if ([String]::IsNullOrEmpty($appResponse)) {
                    $pt = ""
                }
                else {
                    $pt = $appResponse.Substring(0)
                }
                $pt | Out-File -FilePath $pt_decrypt_file -Force -Encoding utf8
                            
                $compareValue = FIPSCompareMD5 -pt_before $pt_encrypt_file -pt_after $pt_decrypt_file  
                if ($compareValue) {
                    # $test_results["result"] = "Passed"
                    $ReturnValue.result = $true
                    Win-DebugTimestamp -output ( "`t test $($tcId) Passed!")
                }
                else {
                    # $test_results["result"] = "Failed"
                    $ReturnValue.result = $false
                    Win-DebugTimestamp -output ( "`t test $($tcId) Failed!")
                }
            }
        }
    }
    else {
        if ($outputResponse -match "decrypt failed") {
            # $test_results["test decrypt"] = "decrypt Failed"
            $ReturnValue.result = $false
            Win-DebugTimestamp -output ( "`t test $($tcId) decrypt Failed!")
        }
        else {
            if ([String]::IsNullOrEmpty($appResponse)) {
                $pt = ""
            }
            else {
                $pt = $appResponse.Substring(0)
            }
            $pt | Out-File -FilePath $pt_decrypt_random_file -Force -Encoding utf8
    
            $compareValue = FIPSCompareMD5 -pt_before $pt_encrypt_random_file -pt_after $pt_decrypt_random_file  
            if ($compareValue) {
                $ReturnValue.result = $true
                Win-DebugTimestamp -output ( "`t test $($tcId) Passed!")
            }
            else {
                $ReturnValue.result = $false
                Win-DebugTimestamp -output ( "`t test $($tcId) Failed!")
            }
        }
    }
    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $FIPSResultPath | out-null
}

function FIPS-Entry {
    Param(
        [Parameter(Mandatory = $True)]
        [string]$_tgId,

        [Parameter(Mandatory = $True)]
        [string]$_tcId,

        [Parameter(Mandatory = $True)]
        [string]$_direction,
    
        [string]$_in,
    
        [string]$_key,
    
        [string]$_iv,
    
        [string]$_aad,
    
        [Parameter(Mandatory = $True)]
        [string]$_aadLen,

        [Parameter(Mandatory = $True)]
        [string]$_tagLen,
    
        [Parameter(Mandatory = $True)]
        [string]$_payloadLen,

        [Parameter(Mandatory = $True)]
        [bool]$Remote
    )

    $ReturnValue = [hashtable] @{
        result    = $true
        error     = "no_error"
        testcases = [System.Array] @()
    }

    WBase-GenerateInfoFile | out-null

    $ProcessList = [hashtable] @{}
    $ProcessIDArray = [System.Array] @()
    $PlatformList = [System.Array] @()
    if ($Remote) {
        $PlatformList = $LocationInfo.VM.NameArray
    }
    else {
        $PlatformList += "Host"
    }

    # Run FIPS as process
    $PlatformList | ForEach-Object {
        $FIPSProcessArgs = "FIPS-Process"
        if ($Remote) {
            $FIPSProcessArgs = "{0} -tgId {1}" -f $FIPSProcessArgs, $_tgId
            $FIPSProcessArgs = "{0} -tcId {1}" -f $FIPSProcessArgs, $_tcId
            $FIPSProcessArgs = "{0} -direction {1}" -f $FIPSProcessArgs, $_direction
            $FIPSProcessArgs = "{0} -in {1}" -f $FIPSProcessArgs, $_in
            $FIPSProcessArgs = "{0} -key {1}" -f $FIPSProcessArgs, $_key
            $FIPSProcessArgs = "{0} -iv_ {1}" -f $FIPSProcessArgs, $_iv
            $FIPSProcessArgs = "{0} -aad {1}" -f $FIPSProcessArgs, $_aad
            $FIPSProcessArgs = "{0} -aadLen {1}" -f $FIPSProcessArgs, $_aadLen
            $FIPSProcessArgs = "{0} -tagLen {1}" -f $FIPSProcessArgs, $_tagLen
            $FIPSProcessArgs = "{0} -payloadLen {1}" -f $FIPSProcessArgs, $_payloadLen
            $FIPSProcessArgs = "{0} -Remote 1" -f $FIPSProcessArgs
            $FIPSProcessArgs = "{0} -VMNameSuffix {1}" -f $FIPSProcessArgs, $_
        }
        else {
            $FIPSProcessArgs = "{0} -tgId {1}" -f $FIPSProcessArgs, $_tgId
            $FIPSProcessArgs = "{0} -tcId {1}" -f $FIPSProcessArgs, $_tcId
            $FIPSProcessArgs = "{0} -direction {1}" -f $FIPSProcessArgs, $_direction
            $FIPSProcessArgs = "{0} -in {1}" -f $FIPSProcessArgs, $_in
            $FIPSProcessArgs = "{0} -key {1}" -f $FIPSProcessArgs, $_key
            $FIPSProcessArgs = "{0} -iv_ {1}" -f $FIPSProcessArgs, $_iv
            $FIPSProcessArgs = "{0} -aad {1}" -f $FIPSProcessArgs, $_aad
            $FIPSProcessArgs = "{0} -aadLen {1}" -f $FIPSProcessArgs, $_aadLen
            $FIPSProcessArgs = "{0} -tagLen {1}" -f $FIPSProcessArgs, $_tagLen
            $FIPSProcessArgs = "{0} -payloadLen {1}" -f $FIPSProcessArgs, $_payloadLen
            $FIPSProcessArgs = "{0} -Remote 0" -f $FIPSProcessArgs
        }
        $FIPSProcessKeyWords = "FIPS_{0}_tgId_{1}_tcId_{2}" -f $_,$_tgId,$_tcId
        $FIPSProcessArgs = "{0} -keyWords {1}" -f $FIPSProcessArgs, $FIPSProcessKeyWords

        $FIPSProcess = WBase-StartProcess `
            -ProcessFilePath "pwsh" `
            -ProcessArgs $FIPSProcessArgs `
            -keyWords $FIPSProcessKeyWords `
            -Remote $false

        $ProcessList[$_] = [hashtable] @{
            Output = $FIPSProcess.Output
            Error  = $FIPSProcess.Error
            Result = $FIPSProcess.Result
        }

        $ProcessIDArray += $FIPSProcess.ID
    }

    # Wait for FIPS process
    WBase-WaitProcessToCompletedByID `
        -ProcessID $ProcessIDArray `
        -Remote $false | out-null
        
    # Check output and error log for FIPS process
    $PlatformList | ForEach-Object {
        $FIPSProcessKeyWords = "FIPS_{0}" -f $_

        $FIPSResult = WBase-CheckProcessOutput `
            -ProcessOutputLogPath $ProcessList[$_].Output `
            -ProcessErrorLogPath $ProcessList[$_].Error `
            -ProcessResultPath $ProcessList[$_].Result `
            -Remote $false `
            -keyWords $FIPSProcessKeyWords `
            -CheckResultFlag $true `
            -CheckResultType "Base"

        if ($ReturnValue.result) {
            $ReturnValue.result = $FIPSResult.result
            $ReturnValue.error = $FIPSResult.error
        }
    }

    return $ReturnValue
}


function FIPStest {
    param (
        [Parameter(Mandatory = $True)]
        [string]$ProcessKeyWords,
    
        [Parameter(Mandatory = $True)]
        [string]$ProcessFilePath,
    
        [Parameter(Mandatory = $True)]
        [string]$direction,
    
        [string]$in_file,
    
        [string]$key_file,
    
        [string]$iv_file,
    
        [string]$aad_file,
    
        [Parameter(Mandatory = $True)]
        [string]$tagLen,
    
        [Parameter(Mandatory = $True)]
        [string]$payloadLen,
    
        [bool]$Remote,
    
        [string]$Session
    )

    $ReturnValue = [hashtable] @{
        process = $null
    }
    
    if (-not ($in_file -eq '') ) {
        $in_file | Out-File $FIPS.app_in_file -Encoding ascii
    }
        
    if (-not ($key_file -eq '') ) {
        $key_file | Out-File -FilePath $FIPS.app_key_file -Force -Encoding utf8
    }
        
    if (-not ($iv_file -eq '') ) {
        if ("ACVP-AES-ECB" -eq $FIPS.batch.algorithm) {
            "00000000000000000000000000000000" | Out-File -FilePath $FIPS.app_iv_file -Force -Encoding utf8
        }
        else {
            $iv_file | Out-File -FilePath $FIPS.app_iv_file -Force -Encoding utf8
        }
    }
        
    if (-not ($aad_file -eq '') ) {
        $aad_file | Out-File -FilePath $FIPS.app_aad_file -Force -Encoding utf8
    }
    
    $ProcessArgs = "$direction $($FIPS.app_in_file) $($FIPS.app_key_file) $($FIPS.app_iv_file) $($FIPS.app_aad_file) $tagLen $payloadLen $($FIPS.app_out_file)"
    
    if ($Remote) {
        $process = WBase-StartProcess `
            -ProcessFilePath $ProcessFilePath `
            -ProcessArgs $ProcessArgs `
            -keyWords $ProcessKeyWords `
            -Remote $Remote `
            -Session $Session
    }
    else {
        $process = WBase-StartProcess `
            -ProcessFilePath $ProcessFilePath `
            -ProcessArgs $ProcessArgs `
            -keyWords $ProcessKeyWords `
            -Remote $Remote
    }
    
    $ReturnValue.process = $process
    return $ReturnValue
}

function FIPSCompareMD5 {
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
