
$global:FIPSSourcePath = "{0}\\FIPS" -f $STVWinPath
$global:FIPS = [hashtable] @{
    FIPSPath            = "{0}\FIPS" -f $QATTESTPATH
    FIPSSamplePath      = "{0}\FIPS\ACVP-AES-GCM.req" -f $QATTESTPATH
    InputValuePath      = "{0}\\InputValue.json" -f $FIPSSourcePath
    TestCaseJsonPath    = "{0}\\TestCaseResultJson.json" -f $FIPSSourcePath
    InFilePath          = Join-Path -Path $FIPSSourcePath -ChildPath "in.hex"
    KeyFilePath         = Join-Path -Path $FIPSSourcePath -ChildPath "key.hex"
    IvFilePath          = Join-Path -Path $FIPSSourcePath -ChildPath "iv.hex"
    AadFilePath         = Join-Path -Path $FIPSSourcePath -ChildPath "aad.hex"
    OutFilePath         = Join-Path -Path $FIPSSourcePath -ChildPath "out.hex"
}

function FIPS-ENV {

    Param(
        [Parameter(Mandatory=$True)]
        [string]$BertaResultPath,

        [Parameter(Mandatory=$True)]
        [string]$ResultJsonFile,

        [string]$ENVType = "init"
    )

    Set-Variable -Name "FIPSResultJsonFile" -Value ("{0}\\{1}" -f $BertaResultPath, $ResultJsonFile) -Scope global

    if (Test-Path -Path $FIPSResultJsonFile) {
        $FIPSResultJsonFilePath = Split-Path -Path $FIPSResultJsonFile
        $FIPSResultJsonFileName = Split-Path -Path $FIPSResultJsonFile -Leaf
        $FIPSResultFileNameArray = $FIPSResultJsonFileName.split(".")
        for ($i = 0; $i -lt 1000; $i++) {
            $FIPSResultFile = "{0}{1}-{2}.{3}" -f
                $FIPSResultJsonFilePath,
                $FIPSResultFileNameArray[0],
                $i,
                $FIPSResultFileNameArray[1]
            if (-not (Test-Path -Path $FIPSResultFile)) {
                break
            }
        }
        Copy-Item -Path $FIPSResultJsonFile -Destination $FIPSResultFile
        Get-Item -Path $FIPSResultJsonFile | Remove-Item -Recurse
    }
    New-Item -Path $BertaResultPath -Name $ResultJsonFile -ItemType "file" | out-null

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
}

# About process runner
function FIPS-Process {
    Param(
        [Parameter(Mandatory = $True)]
        [string]$TestGroupId,

        [Parameter(Mandatory = $True)]
        [string]$TestCaseId,

        [Parameter(Mandatory = $True)]
        [string]$EncryptDecryptDirection,

        [Parameter(Mandatory = $True)]
        [string]$InputValuePath,

        [Parameter(Mandatory = $True)]
        [string]$AadLen,

        [Parameter(Mandatory = $True)]
        [string]$TagLen,

        [Parameter(Mandatory = $True)]
        [string]$PayloadLen,

        [Parameter(Mandatory = $True)]
        [string]$keyWords,

        [Parameter(Mandatory = $True)]
        [bool]$Remote,

        [string]$VMNameSuffix = $null
    )

    $ReturnValue = [hashtable] @{
        result    = $true
        error     = "no_error"
    }

    $TestCaseResultJson = [hashtable] @{
        pt    = $null
        ct    = $null
        tag   = $null
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
            $LocationInfo.TestCaseName,
            $keyWords
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

    $InputValueHashtable = WBase-ReadHashtableFromJsonFile -InfoFilePath $FIPS.InputValuePath
    $ptBeforeEncryptFilePath = Join-Path -Path $FIPSSourcePath -ChildPath "ptBeforeEncrypt.hex"
    $ptAfterDecryptFilePath = Join-Path -Path $FIPSSourcePath -ChildPath "ptAfterDecrypt.hex"
    $ptRandomBeforeEncryptFilePath = Join-Path -Path $FIPSSourcePath -ChildPath "ptRandomBeforeEncrypt.hex"
    $ptRandomAfterDecryptFilePath = Join-Path -Path $FIPSSourcePath -ChildPath "ptRandomAfterDecrypt.hex"

    $ProcessName = "fips_windows"

    if ($Remote) {
        $ProcessFilePath = "{0}\FIPS\{1}.exe" -f $STVWinPath, $ProcessName
    }
    else {
        $ProcessFilePath = "{0}\{1}.exe" -f $FIPS.FIPSPath, $ProcessName
    }

    #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # beginning of alg dependend section
    #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    if ($EncryptDecryptDirection -eq "encrypt") {
        if ($PayloadLen -eq 0) {
            $InputValueHashtable.InFileContent = ""
        }
        $InputValueHashtable.InFileContent | Out-File -FilePath $FIPS.InFilePath -Force -Encoding utf8
        $InputValueHashtable.InFileContent | Out-File -FilePath $ptBeforeEncryptFilePath -Force -Encoding utf8
    }
    else {
        if ($PayloadLen -eq 0) {
            $ptRandom = ""
            $ptRandom | Out-File -FilePath $FIPS.InFilePath -Force -Encoding utf8
        }
        else {
            $ptRandom = -join (1..($PayloadLen / 4) | % { [char][int]((48..57 + 65..70) | Get-Random) })
        }
        if ($AadLen -eq 0) {
            $InputValueHashtable.AadFileContent = ""
            $InputValueHashtable.AadFileContent | Out-File -FilePath $FIPS.AadFilePath -Force -Encoding utf8
        }
        $ptRandom | Out-File $ptRandomBeforeEncryptFilePath -Encoding ascii

        if ($Remote) {
            $ProcessKeyWords = "Direction_{0}_EncryptForDecrypt" -f $VMNameSuffix
            $inProcess = FIPSBase `
                -ProcessKeyWords $ProcessKeyWords `
                -ProcessFilePath $ProcessFilePath `
                -EncryptDecryptDirection "encrypt" `
                -InFileContent $ptRandom `
                -KeyFileContent $InputValueHashtable.KeyFileContent `
                -IvFileContent $InputValueHashtable.IvFileContent `
                -AadFileContent $InputValueHashtable.AadFileContent `
                -TagLen $TagLen `
                -PayloadLen $PayloadLen `
                -Remote $Remote `
                -Session $Session
        }
        else {
            $ProcessKeyWords = "Direction_EncryptForDecrypt"
            $inProcess = FIPSBase `
                -ProcessKeyWords $ProcessKeyWords `
                -ProcessFilePath $ProcessFilePath `
                -EncryptDecryptDirection "encrypt" `
                -InFileContent $ptRandom `
                -KeyFileContent $InputValueHashtable.KeyFileContent `
                -IvFileContent $InputValueHashtable.IvFileContent `
                -AadFileContent $InputValueHashtable.AadFileContent `
                -TagLen $TagLen `
                -PayloadLen $PayloadLen `
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

        $random_Response = Get-Content $FIPS.OutFilePath
        $random_Response | Out-File -FilePath $FIPS.InFilePath -Force -Encoding utf8
    }
    if ($Remote) {
        if ($AadLen -eq 0) {
            $InputValueHashtable.AadFileContent = ""
            $InputValueHashtable.AadFileContent | Out-File -FilePath $FIPS.AadFilePath -Force -Encoding utf8
        }
        if($EncryptDecryptDirection -eq "encrypt"){
            $ProcessKeyWords = "{0}_Direction_encrypt" -f $VMNameSuffix
        }else{
            $ProcessKeyWords = "{0}_Direction_decryptRandomly" -f $VMNameSuffix
        }
        $inProcess = FIPSBase `
            -ProcessKeyWords $ProcessKeyWords `
            -ProcessFilePath $ProcessFilePath `
            -EncryptDecryptDirection $EncryptDecryptDirection `
            -KeyFileContent $InputValueHashtable.KeyFileContent `
            -IvFileContent $InputValueHashtable.IvFileContent `
            -AadFileContent $InputValueHashtable.AadFileContent `
            -TagLen $TagLen `
            -PayloadLen $PayloadLen `
            -Remote $Remote `
            -Session $Session
    }
    else {
        if ($AadLen -eq 0) {
            $InputValueHashtable.AadFileContent = ""
            $InputValueHashtable.AadFileContent | Out-File -FilePath $FIPS.AadFilePath -Force -Encoding utf8
        }
        if($EncryptDecryptDirection -eq "encrypt"){
            $ProcessKeyWords = "Direction_encrypt"
        }else{
            $ProcessKeyWords = "Direction_decryptRandomly"
        }
        $inProcess = FIPSBase `
            -ProcessKeyWords $ProcessKeyWords `
            -ProcessFilePath $ProcessFilePath `
            -EncryptDecryptDirection $EncryptDecryptDirection `
            -KeyFileContent $InputValueHashtable.KeyFileContent `
            -IvFileContent $InputValueHashtable.IvFileContent `
            -AadFileContent $InputValueHashtable.AadFileContent `
            -TagLen $TagLen `
            -PayloadLen $PayloadLen `
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

    $AppResponse = Get-Content $FIPS.OutFilePath
    $OutputResponse = Get-Content $inProcess.process.Output
    $splitValue = [int]($TagLen / 4)
    if ($EncryptDecryptDirection -eq "encrypt") {
        if ($OutputResponse -match "SymmEncrypt failed") {
            $ReturnValue.result = $false
            Win-DebugTimestamp -output ( "`t test $TestCaseId encrypt Failed!" )
        }
        else {
            $CipherText = $AppResponse.Substring(0, $AppResponse.Length - $splitValue)
            $Tag = $AppResponse.Substring($AppResponse.Length - $splitValue)
            $TestCaseResultJson.ct = $CipherText
            $TestCaseResultJson.tag = $Tag

            #Compare the MD5 values of plaintext before encryption and plaintext after decryption
            $outProcessKeyWords = "Direction_DecryptAfterEncrypt"
            if ($Remote) {
                $outProcess = FIPSBase `
                    -ProcessKeyWords $outProcessKeyWords `
                    -ProcessFilePath $ProcessFilePath `
                    -EncryptDecryptDirection "decrypt" `
                    -InFileContent ($CipherText + $Tag) `
                    -TagLen $TagLen `
                    -PayloadLen $PayloadLen `
                    -Remote $Remote `
                    -Session $Session
            }
            else {
                $outProcess = FIPSBase `
                    -ProcessKeyWords $outProcessKeyWords `
                    -ProcessFilePath $ProcessFilePath `
                    -EncryptDecryptDirection "decrypt" `
                    -InFileContent ($CipherText + $Tag) `
                    -TagLen $TagLen `
                    -PayloadLen $PayloadLen `
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

            $AppResponse = Get-Content $FIPS.OutFilePath
            $OutputResponse = Get-Content $outProcess.process.Output
            if ($OutputResponse -match "decrypt failed") {
                $ReturnValue.result = $false
                Win-DebugTimestamp -output ( "`t test $TestCaseId decrypt Failed!")
            }
            else {
                if ([String]::IsNullOrEmpty($AppResponse)) {
                    $PlainText = ""
                }
                else {
                    $PlainText = $AppResponse.Substring(0)
                }
                $PlainText | Out-File -FilePath $ptAfterDecryptFilePath -Force -Encoding utf8

                $CompareValue = FIPSCompareMD5 `
                    -ptBeforeEncryptFilePath $ptBeforeEncryptFilePath `
                    -ptAfterDecryptFilePath $ptAfterDecryptFilePath
                if ($CompareValue) {
                    $ReturnValue.result = $true
                    Win-DebugTimestamp -output ( "`t test $TestCaseId Passed!")
                }
                else {
                    $ReturnValue.result = $false
                    Win-DebugTimestamp -output ( "`t test $TestCaseId Failed!")
                }
            }
        }
    }
    else {
        if ($OutputResponse -match "decrypt failed") {
            $ReturnValue.result = $false
            Win-DebugTimestamp -output ( "`t test $TestCaseId decrypt randomly Failed!")
        }
        else {
            if ([String]::IsNullOrEmpty($AppResponse)) {
                $PlainText = ""
            }
            else {
                $PlainText = $AppResponse.Substring(0)
            }
            $PlainText | Out-File -FilePath $ptRandomAfterDecryptFilePath -Force -Encoding utf8

            $CompareValue = FIPSCompareMD5 `
                -ptBeforeEncryptFilePath $ptRandomBeforeEncryptFilePath `
                -ptAfterDecryptFilePath $ptRandomAfterDecryptFilePath
            if ($CompareValue) {
                $ReturnValue.result = $true
                Win-DebugTimestamp -output ( "`t test $TestCaseId Passed!")
            }
            else {
                $ReturnValue.result = $false
                Win-DebugTimestamp -output ( "`t test $TestCaseId Failed!")
            }
        }

        #Decyrpt the case normally for FIPSResultJsonFile
        $ProcessKeyWords = "Direction_decryptNormally"
        $decryptNormalProcess = FIPSBase `
            -ProcessKeyWords $ProcessKeyWords `
            -ProcessFilePath $ProcessFilePath `
            -EncryptDecryptDirection $EncryptDecryptDirection `
            -InFileContent $InputValueHashtable.InFileContent `
            -KeyFileContent $InputValueHashtable.KeyFileContent `
            -IvFileContent $InputValueHashtable.IvFileContent `
            -AadFileContent $InputValueHashtable.AadFileContent `
            -TagLen $TagLen `
            -PayloadLen $PayloadLen `
            -Remote $Remote

        if ($Remote) {
            WBase-WaitProcessToCompletedByID `
                -ProcessID $decryptNormalProcess.process.ID `
                -Remote $Remote `
                -Session $Session
        }
        else {
            WBase-WaitProcessToCompletedByID `
                -ProcessID $decryptNormalProcess.process.ID `
                -Remote $Remote
        }

        $AppResponse = Get-Content $FIPS.OutFilePath
        $OutputResponse = Get-Content $decryptNormalProcess.process.Output
        if ($OutputResponse -match "decrypt failed") {
            Win-DebugTimestamp -output ( "`t test $TestCaseId decrypt normally Failed!")
        }else{
            if ([String]::IsNullOrEmpty($AppResponse)) {
                $TestCaseResultJson.pt = ""
            }
            else {
                $TestCaseResultJson.pt = $AppResponse.Substring(0)
            }
        }
    }
    WBase-WriteHashtableToJsonFile `
        -Info $ReturnValue `
        -InfoFilePath $FIPSResultPath | out-null

    WBase-WriteHashtableToJsonFile `
        -Info $TestCaseResultJson `
        -InfoFilePath $FIPS.TestCaseJsonPath | out-null
}

function FIPS-Entry {
    Param(
        [Parameter(Mandatory = $True)]
        [string]$TestGroupId,

        [Parameter(Mandatory = $True)]
        [string]$TestCaseId,

        [Parameter(Mandatory = $True)]
        [string]$EncryptDecryptDirection,

        [Parameter(Mandatory = $True)]
        [string]$InputValuePath,

        [Parameter(Mandatory = $True)]
        [string]$AadLen,

        [Parameter(Mandatory = $True)]
        [string]$TagLen,

        [Parameter(Mandatory = $True)]
        [string]$PayloadLen,

        [Parameter(Mandatory = $True)]
        [bool]$Remote
    )

    $ReturnValue = [hashtable] @{
        result    = $true
        error     = "no_error"
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
            $FIPSProcessArgs = "{0} -TestGroupId {1}" -f $FIPSProcessArgs, $TestGroupId
            $FIPSProcessArgs = "{0} -TestCaseId {1}" -f $FIPSProcessArgs, $TestCaseId
            $FIPSProcessArgs = "{0} -EncryptDecryptDirection {1}" -f $FIPSProcessArgs, $EncryptDecryptDirection
            $FIPSProcessArgs = "{0} -InputValuePath {1}" -f $FIPSProcessArgs, $FIPS.InputValuePath
            $FIPSProcessArgs = "{0} -AadLen {1}" -f $FIPSProcessArgs, $AadLen
            $FIPSProcessArgs = "{0} -TagLen {1}" -f $FIPSProcessArgs, $TagLen
            $FIPSProcessArgs = "{0} -PayloadLen {1}" -f $FIPSProcessArgs, $PayloadLen
            $FIPSProcessArgs = "{0} -Remote 1" -f $FIPSProcessArgs
            $FIPSProcessArgs = "{0} -VMNameSuffix {1}" -f $FIPSProcessArgs, $_
        }
        else {
            $FIPSProcessArgs = "{0} -TestGroupId {1}" -f $FIPSProcessArgs, $TestGroupId
            $FIPSProcessArgs = "{0} -TestCaseId {1}" -f $FIPSProcessArgs, $TestCaseId
            $FIPSProcessArgs = "{0} -EncryptDecryptDirection {1}" -f $FIPSProcessArgs, $EncryptDecryptDirection
            $FIPSProcessArgs = "{0} -InputValuePath {1}" -f $FIPSProcessArgs, $FIPS.InputValuePath
            $FIPSProcessArgs = "{0} -AadLen {1}" -f $FIPSProcessArgs, $AadLen
            $FIPSProcessArgs = "{0} -TagLen {1}" -f $FIPSProcessArgs, $TagLen
            $FIPSProcessArgs = "{0} -PayloadLen {1}" -f $FIPSProcessArgs, $PayloadLen
            $FIPSProcessArgs = "{0} -Remote 0" -f $FIPSProcessArgs
        }
        $FIPSProcessKeyWords = "FIPS_{0}" -f $_
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

function FIPSBase {
    param (
        [Parameter(Mandatory = $True)]
        [string]$ProcessKeyWords,

        [Parameter(Mandatory = $True)]
        [string]$ProcessFilePath,

        [Parameter(Mandatory = $True)]
        [string]$EncryptDecryptDirection,

        [Parameter(Mandatory = $True)]
        [string]$TagLen,

        [Parameter(Mandatory = $True)]
        [string]$PayloadLen,

        [Parameter(Mandatory = $True)]
        [bool]$Remote,

        [string]$InFileContent = $null,

        [string]$KeyFileContent = $null,

        [string]$IvFileContent = $null,

        [string]$AadFileContent = $null,

        [object]$Session = $null
    )

    $TestCaseBatch = Get-Content -Path $FIPS.FIPSSamplePath | ConvertFrom-Json

    $ReturnValue = [hashtable] @{
        process = $null
    }

    if (-not ([String]::IsNullOrEmpty($InFileContent)) ) {
        $InFileContent | Out-File $FIPS.InFilePath -Encoding ascii
    }

    if (-not ([String]::IsNullOrEmpty($keyFileContent)) ) {
        $keyFileContent | Out-File -FilePath $FIPS.KeyFilePath -Force -Encoding utf8
    }

    if (-not ([String]::IsNullOrEmpty($IvFileContent)) ) {
        if ("ACVP-AES-ECB" -eq $TestCaseBatch.algorithm) {
            "00000000000000000000000000000000" | Out-File -FilePath $FIPS.IvFilePath -Force -Encoding utf8
        }
        else {
            $IvFileContent | Out-File -FilePath $FIPS.IvFilePath -Force -Encoding utf8
        }
    }

    if (-not ([String]::IsNullOrEmpty($AadFileContent)) ) {
        $AadFileContent | Out-File -FilePath $FIPS.AadFilePath -Force -Encoding utf8
    }

    $ProcessArgs = "{0} {1} {2} {3} {4} {5} {6} {7}" -f
        $EncryptDecryptDirection,
        $FIPS.InFilePath,
        $FIPS.KeyFilePath,
        $FIPS.IvFilePath,
        $FIPS.AadFilePath,
        $TagLen,
        $PayloadLen,
        $FIPS.OutFilePath

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
        [string]$ptBeforeEncryptFilePath,

        [Parameter(Mandatory = $True)]
        [string]$ptAfterDecryptFilePath
    )
    $ReturnValue = $false
    $ptBeforeEncryptHash = certutil -hashfile $ptBeforeEncryptFilePath MD5
    $ptAfterDecryptHash = certutil -hashfile $ptAfterDecryptFilePath MD5
    if ($ptBeforeEncryptHash[1] -eq $ptAfterDecryptHash[1]) {
        $ReturnValue = $true
    }
    else {
        $ReturnValue = $false
    }
    return $ReturnValue
}


Export-ModuleMember -Variable *-*
Export-ModuleMember -Function *-*