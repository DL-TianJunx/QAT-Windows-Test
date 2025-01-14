
# About tracelog tool
function UT-TraceLogStart
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $TraceLogType = "Remote"
        $TraceLogCheckFlags = $LocationInfo.PDBNameArray.Remote
    } else {
        $LogKeyWord = "Host"
        $TraceLogType = "Host"
        $TraceLogCheckFlags = $LocationInfo.PDBNameArray.Host
    }

    Win-DebugTimestamp -output ("{0}: Start tracelog tool..." -f $LogKeyWord)

    if ($Remote) {
        $TraceLogCheckStatus = Invoke-Command -Session $Session -ScriptBlock {
            Param($TraceLogCheckFlags, $TraceLogOpts)
            $ReturnValue = [hashtable] @{}

            ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
                $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag]
                $StartFlag = $true

                if ($checkProcess[0] -match "successfully") {
                    if (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag]) {
                        &$TraceLogOpts.ExePath -flush $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag] | out-null
                        $StartFlag = $false
                    } else {
                        &$TraceLogOpts.ExePath -stop $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag] | out-null
                        $StartFlag = $true
                        Start-Sleep -Seconds 5
                    }
                }

                if ($StartFlag) {
                    &$TraceLogOpts.ExePath `
                        -start $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag] `
                        -f $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag] `
                        -guid $TraceLogOpts.Guid[$TraceLogCheckFlag] `
                        -rt `
                        -level 3 `
                        -matchanykw 0xFFFFFFFF `
                        -b 1000 `
                        -ft 1 `
                        -min 4 `
                        -max 21 `
                        -hybridshutdown stop | out-null
                }

                $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag]
                if ($checkProcess[0] -match "successfully") {
                    if (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag]) {
                        $ReturnValue[$TraceLogCheckFlag] = $true
                    } else {
                        $ReturnValue[$TraceLogCheckFlag] = $false
                    }
                } else {
                    $ReturnValue[$TraceLogCheckFlag] = $false
                }
            }

            return $ReturnValue
        } -ArgumentList $TraceLogCheckFlags, $TraceLogOpts
    } else {
        $TraceLogCheckStatus = [hashtable] @{}
        ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
            $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag]
            $StartFlag = $true

            if ($checkProcess[0] -match "successfully") {
                if (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag]) {
                    &$TraceLogOpts.ExePath -flush $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag] | out-null
                    $StartFlag = $false
                } else {
                    &$TraceLogOpts.ExePath -stop $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag] | out-null
                    $StartFlag = $true
                    Start-Sleep -Seconds 5
                }
            }

            if ($StartFlag) {
                &$TraceLogOpts.ExePath `
                    -start $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag] `
                    -f $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag] `
                    -guid $TraceLogOpts.Guid[$TraceLogCheckFlag] `
                    -rt `
                    -level 4 `
                    -matchanykw 0xFFFFFFFF `
                    -b 1000 `
                    -ft 1 `
                    -min 4 `
                    -max 21 `
                    -hybridshutdown stop | out-null
            }

            $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag]
            if ($checkProcess[0] -match "successfully") {
                if (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag]) {
                    $TraceLogCheckStatus[$TraceLogCheckFlag] = $true
                } else {
                    $TraceLogCheckStatus[$TraceLogCheckFlag] = $false
                }
            } else {
                $TraceLogCheckStatus[$TraceLogCheckFlag] = $false
            }
        }
    }

    ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
        if ($TraceLogCheckStatus[$TraceLogCheckFlag]) {
            Win-DebugTimestamp -output (
                "{0}: The process named '{1}' is working" -f
                    $LogKeyWord,
                    $TraceLogOpts.SessionName[$TraceLogType][$TraceLogCheckFlag]
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: The process named '{1}' is not working" -f
                    $LogKeyWord,
                    $TraceLogOpts.SessionName[$TraceLogType][$TraceLogCheckFlag]
            )
        }
    }
}

function UT-TraceLogStop
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $TraceLogType = "Remote"
        $TraceLogCheckFlags = $LocationInfo.PDBNameArray.Remote
    } else {
        $LogKeyWord = "Host"
        $TraceLogType = "Host"
        $TraceLogCheckFlags = $LocationInfo.PDBNameArray.Host
    }

    Win-DebugTimestamp -output ("{0}: Stop tracelog tool..." -f $LogKeyWord)

    if ($Remote) {
        $TraceLogCheckStatus = Invoke-Command -Session $Session -ScriptBlock {
            Param($TraceLogCheckFlags, $TraceLogOpts)
            $ReturnValue = [hashtable] @{}

            ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
                $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag]
                if ($checkProcess[0] -match "successfully") {
                    &$TraceLogOpts.ExePath -stop $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag] | out-null
                    Start-Sleep -Seconds 5
                }

                $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Remote[$TraceLogCheckFlag]
                if ($checkProcess[0] -match "recognized") {
                    if (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag]) {
                        $ReturnValue[$TraceLogCheckFlag] = $true
                    } else {
                        $ReturnValue[$TraceLogCheckFlag] = $false
                    }
                } else {
                    $ReturnValue[$TraceLogCheckFlag] = $false
                }
            }

            return $ReturnValue
        } -ArgumentList $TraceLogCheckFlags, $TraceLogOpts
    } else {
        $TraceLogCheckStatus = [hashtable] @{}
        ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
            $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag]
            if ($checkProcess[0] -match "successfully") {
                &$TraceLogOpts.ExePath -stop $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag] | out-null
                Start-Sleep -Seconds 5
            }

            $checkProcess = &$TraceLogOpts.ExePath -q $TraceLogOpts.SessionName.Host[$TraceLogCheckFlag]
            if ($checkProcess[0] -match "recognized") {
                if (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag]) {
                    $TraceLogCheckStatus[$TraceLogCheckFlag] = $true
                } else {
                    $TraceLogCheckStatus[$TraceLogCheckFlag] = $false
                }
            } else {
                $TraceLogCheckStatus[$TraceLogCheckFlag] = $false
            }
        }
    }

    ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
        if ($TraceLogCheckStatus[$TraceLogCheckFlag]) {
            Win-DebugTimestamp -output (
                "{0}: The process named '{1}' is stopped" -f
                    $LogKeyWord,
                    $TraceLogOpts.SessionName[$TraceLogType][$TraceLogCheckFlag]
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: The process named '{1}' is not stopped" -f
                    $LogKeyWord,
                    $TraceLogOpts.SessionName[$TraceLogType][$TraceLogCheckFlag]
            )
        }
    }
}

function UT-TraceLogTransfer
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $TraceLogType = "Remote"
        $TraceLogCheckFlags = $LocationInfo.PDBNameArray.Remote
    } else {
        $LogKeyWord = "Host"
        $TraceLogType = "Host"
        $TraceLogCheckFlags = $LocationInfo.PDBNameArray.Host
    }

    Win-DebugTimestamp -output ("{0}: Transfer events to log..." -f $LogKeyWord)

    if ($Remote) {
        $TraceLogCheckStatus = Invoke-Command -Session $Session -ScriptBlock {
            Param($TraceLogCheckFlags, $TraceLogOpts)
            $ReturnValue = [hashtable] @{}

            $CommandArgs = "-f {0}\\*.pdb -p {1} 2>&1" -f
                $TraceLogOpts.PDBPath,
                $TraceLogOpts.FMTPath
            Start-Process -FilePath  $TraceLogOpts.PDBExePath `
                          -ArgumentList $CommandArgs `
                          -NoNewWindow `
                          -Wait | out-null

            ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
                $ReturnValue[$TraceLogCheckFlag] = $true
                if (-not (Test-Path -Path $TraceLogOpts.PDBFullPath[$TraceLogCheckFlag])) {
                    $ReturnValue[$TraceLogCheckFlag] = $false
                }

                if (-not (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag])) {
                    $ReturnValue[$TraceLogCheckFlag] = $false
                }

                if ($ReturnValue[$TraceLogCheckFlag]) {
                    $CommandArgs = "{0} -p {1} -o {2} -nosummary" -f
                        $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag],
                        $TraceLogOpts.FMTPath,
                        $TraceLogOpts.LogFullPath[$TraceLogCheckFlag]
                    Start-Process -FilePath  $TraceLogOpts.FMTExePath `
                                  -ArgumentList $CommandArgs `
                                  -NoNewWindow `
                                  -Wait | out-null

                    if (Test-Path -Path $TraceLogOpts.LogFullPath[$TraceLogCheckFlag]) {
                        $ReturnValue[$TraceLogCheckFlag] = $true
                    } else {
                        $ReturnValue[$TraceLogCheckFlag] = $false
                    }
                }
            }

            return $ReturnValue
        } -ArgumentList $TraceLogCheckFlags, $TraceLogOpts
    } else {
        $CommandArgs = "-f {0}\\*.pdb -p {1} 2>&1" -f
            $TraceLogOpts.PDBPath,
            $TraceLogOpts.FMTPath
        Start-Process -FilePath  $TraceLogOpts.PDBExePath `
                      -ArgumentList $CommandArgs `
                      -NoNewWindow `
                      -Wait | out-null

        $TraceLogCheckStatus = [hashtable] @{}
        ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
            $TraceLogCheckStatus[$TraceLogCheckFlag] = $true
            if (-not (Test-Path -Path $TraceLogOpts.PDBFullPath[$TraceLogCheckFlag])) {
                $TraceLogCheckStatus[$TraceLogCheckFlag] = $false
            }

            if (-not (Test-Path -Path $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag])) {
                $TraceLogCheckStatus[$TraceLogCheckFlag] = $false
            }

            if ($TraceLogCheckStatus[$TraceLogCheckFlag]) {
                $CommandArgs = "{0} -p {1} -o {2} -nosummary" -f
                    $TraceLogOpts.EtlFullPath[$TraceLogCheckFlag],
                    $TraceLogOpts.FMTPath,
                    $TraceLogOpts.LogFullPath[$TraceLogCheckFlag]
                Start-Process -FilePath  $TraceLogOpts.FMTExePath `
                              -ArgumentList $CommandArgs `
                              -NoNewWindow `
                              -Wait | out-null

                if (Test-Path -Path $TraceLogOpts.LogFullPath[$TraceLogCheckFlag]) {
                    $TraceLogCheckStatus[$TraceLogCheckFlag] = $true
                } else {
                    $TraceLogCheckStatus[$TraceLogCheckFlag] = $false
                }
            }
        }
    }

    ForEach ($TraceLogCheckFlag in $TraceLogCheckFlags) {
        if ($TraceLogCheckStatus[$TraceLogCheckFlag]) {
            Win-DebugTimestamp -output (
                "{0}: The transfer is successful > {1}" -f
                    $LogKeyWord,
                    $TraceLogOpts.LogFullPath[$TraceLogCheckFlag]
            )
        } else {
            Win-DebugTimestamp -output (
                "{0}: The transfer is unsuccessful" -f $LogKeyWord
            )
        }
    }
}

function UT-TraceLogCheck
{
    $ReturnValue = $true

    UT-TraceLogStop -Remote $false | out-null
    UT-TraceLogTransfer -Remote $false | out-null
    $TraceViewContent = Get-Content -Path $TraceLogOpts.LogFullPath.IcpQat

    Foreach ($Number in (0 .. ($LocationInfo.PF.Number - 1))) {
        $startQatDevice = "qat_dev{0} started" -f $Number
        $stopQatDevice = "qat_dev{0} stopped" -f $Number

        if ($TraceViewContent -match $stopQatDevice) {
            Win-DebugTimestamp -output ("Qat device {0} is stopped" -f $Number)
        } else {
            Win-DebugTimestamp -output ("Qat device {0} is not stopped" -f $Number)
            if ($ReturnValue) {$ReturnValue = $false}
        }

        if ($TraceViewContent -match $startQatDevice) {
            Win-DebugTimestamp -output ("Qat device {0} is started" -f $Number)
        } else {
            Win-DebugTimestamp -output ("Qat device {0} is not started" -f $Number)
            if ($ReturnValue) {$ReturnValue = $false}
        }
    }

    return $ReturnValue
}

# About driver verifier
function UT-SetDriverVerifier
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$DriverVerifier,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $false

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $RemoteReturnValue = Invoke-Command -Session $Session -ScriptBlock {
            Param($DriverVerifierArgs, $DriverVerifier)
            $VerifierReturn = $false

            if ($DriverVerifier) {
                $VerifierOutput = &$DriverVerifierArgs.ExePath $DriverVerifierArgs.Start.split() $DriverVerifierArgs.Servers.split()
            } else {
                $VerifierOutput = &$DriverVerifierArgs.ExePath $DriverVerifierArgs.Delete.split()
            }

            $VerifierOutput | ForEach-Object {
                if ($_ -match $DriverVerifierArgs.SuccessLog) {$VerifierReturn = $true}
                if ($_ -match $DriverVerifierArgs.NoChangeLog) {$VerifierReturn = $true}
            }

            return $VerifierReturn
        } -ArgumentList $DriverVerifierArgs, $DriverVerifier

        $ReturnValue = $RemoteReturnValue
    } else {
        $LogKeyWord = "Host"
        if ($DriverVerifier) {
            $VerifierCommand = "{0} {1} {2}" -f
                $DriverVerifierArgs.ExePath,
                $DriverVerifierArgs.Start,
                $DriverVerifierArgs.Servers
        } else {
            $VerifierCommand = "{0} {1}" -f
                $DriverVerifierArgs.ExePath,
                $DriverVerifierArgs.Delete
        }

        $VerifierOutput = Invoke-Expression $VerifierCommand 2>&1
        $VerifierOutput | ForEach-Object {
            if ($_ -match $DriverVerifierArgs.SuccessLog) {$ReturnValue = $true}
            if ($_ -match $DriverVerifierArgs.NoChangeLog) {$ReturnValue = $true}
        }
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Set driver verifier as {1} is successful" -f $LogKeyWord, $DriverVerifier
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Set driver verifier as {1} is unsuccessful" -f $LogKeyWord, $DriverVerifier
        )
    }

    return $ReturnValue
}

function UT-CheckDriverVerifier
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$CheckFlag,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $false

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    Win-DebugTimestamp -output (
        "{0}: Check driver verifier as {1}" -f $LogKeyWord, $CheckFlag
    )

    if ($Remote) {
        $Verifier = Invoke-Command -Session $Session -ScriptBlock {
            Param($DriverVerifierArgs)
            $Verifier = $true
            $MessageFlag = $false

            $VerifierOutput = &$DriverVerifierArgs.ExePath $DriverVerifierArgs.List.split() 2>&1
            $VerifierOutput | ForEach-Object {
                if ($MessageFlag) {
                    if ($_ -match "None") {
                        $Verifier = $false
                    }
                }

                if ($_ -match "Verified Drivers") {
                    $MessageFlag = $true
                }
            }
            return $Verifier
        } -ArgumentList $DriverVerifierArgs
    } else {
        $Verifier = $true
        $MessageFlag = $false
        $VerifierCommand = "{0} {1}" -f
            $DriverVerifierArgs.ExePath,
            $DriverVerifierArgs.List

        $VerifierOutput = Invoke-Expression $VerifierCommand 2>&1
        $VerifierOutput | ForEach-Object {
            if ($MessageFlag) {
                if ($_ -match "None") {
                    $Verifier = $false
                }
            }

            if ($_ -match "Verified Drivers") {
                $MessageFlag = $true
            }
        }
    }

    if ($CheckFlag -eq $Verifier) {
        Win-DebugTimestamp -output (
            "{0}: Check driver verifier > passed" -f $LogKeyWord
        )

        $ReturnValue = $true
    } else {
        Win-DebugTimestamp -output (
            "{0}: Check driver verifier > failed, will be reset" -f $LogKeyWord
        )

        $ReturnValue = $false
    }

    return $ReturnValue
}

# About service
function UT-CreateService
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ServiceName,

        [Parameter(Mandatory=$True)]
        [string]$ServiceFile,

        [Parameter(Mandatory=$True)]
        [string]$ServiceCert,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    Win-DebugTimestamp -output (
        "{0}: Create server '{1}' from '{2}'" -f
            $LogKeyWord,
            $ServiceName,
            $ServiceFile
    )

    $ScriptBlock = {
        Param($ServiceName, $ServiceFile)
        $ReturnValue = $false

        $ServiceFileName = Split-Path -Path $ServiceFile -Leaf
        $LocalServiceFile = "C:\Windows\\System32\\drivers\\{0}" -f $ServiceFileName
        if (-not (Test-Path -Path $LocalServiceFile)) {
            Copy-Item -Path $ServiceFile -Destination $LocalServiceFile
        }

        $GetServiceError = $null
        $ServiceOb = Get-Service `
            -Name $ServiceName `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetServiceError
        if ([String]::IsNullOrEmpty($GetServiceError)) {
            if ($ServiceOb.Status -eq "Running") {
                Stop-Service -Name $ServiceName | out-null
            }

            Remove-Service -Name $ServiceName | out-null
        }

        sc create qzfor type=kernel start=demand binpath=$LocalServiceFile
        Start-Service -Name $ServiceName | out-null

        $GetServiceError = $null
        $ServiceOb = Get-Service `
            -Name $ServiceName `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetServiceError
        if ([String]::IsNullOrEmpty($GetServiceError)) {
            $ReturnValue = $true
        }

        return $ReturnValue
    }

    if ($Remote) {
        UT-SetCertificate `
            -CertFile $ServiceCert `
            -Remote $Remote `
            -Session $Session | out-null

        $CreateStatus = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ServiceName, $ServiceFile
    } else {
        UT-SetCertificate `
            -CertFile $ServiceCert `
            -Remote $Remote | out-null

        $CreateStatus = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ServiceName, $ServiceFile
    }

    if ($CreateStatus) {
        Win-DebugTimestamp -output (
            "{0}: Create server is successful" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Create server is unsuccessful" -f $LogKeyWord
        )
    }
}

function UT-RemoveService
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$ServiceName,

        [Parameter(Mandatory=$True)]
        [string]$ServiceFile,

        [Parameter(Mandatory=$True)]
        [string]$ServiceCert,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    $ServiceFileName = Split-Path -Path $ServiceFile -Leaf
    $LocalServiceFile = "C:\Windows\\System32\\drivers\\{0}" -f $ServiceFileName

    Win-DebugTimestamp -output (
        "{0}: Remove server '{1}' and '{2}'" -f
            $LogKeyWord,
            $ServiceName,
            $LocalServiceFile
    )

    $ScriptBlock = {
        Param($ServiceName, $LocalServiceFile)
        $ReturnValue = $false

        $GetServiceError = $null
        $ServiceOb = Get-Service `
            -Name $ServiceName `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetServiceError
        if ([String]::IsNullOrEmpty($GetServiceError)) {
            if ($ServiceOb.Status -eq "Running") {
                Stop-Service -Name $ServiceName | out-null
            }
            Remove-Service -Name $ServiceName | out-null
        }

        if (Test-Path -Path $LocalServiceFile) {
            Get-Item -Path $LocalServiceFile | Remove-Item -Force
        }

        $GetServiceError = $null
        $ServiceOb = Get-Service `
            -Name $ServiceName `
            -ErrorAction SilentlyContinue `
            -ErrorVariable GetServiceError
        if (-not [String]::IsNullOrEmpty($GetServiceError)) {
            $ReturnValue = $true
        }
    }

    if ($Remote) {
        $RemoveStatus = Invoke-Command `
            -Session $Session `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ServiceName, $LocalServiceFile

        UT-DelCertificate `
            -CertFile $ServiceCert `
            -Remote $Remote `
            -Session $Session | out-null
    } else {
        $RemoveStatus = Invoke-Command `
            -ScriptBlock $ScriptBlock `
            -ArgumentList $ServiceName, $LocalServiceFile

        UT-DelCertificate `
            -CertFile $ServiceCert `
            -Remote $Remote | out-null
    }

    if ($RemoveStatus) {
        Win-DebugTimestamp -output (
            "{0}: Remove server is successful" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Remove server is unsuccessful" -f $LogKeyWord
        )
    }
}

# About bcdedit
function UTSetBCDEDITValue
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$BCDEDITKey,

        [Parameter(Mandatory=$True)]
        [string]$BCDEDITValue,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $false

    if ($Remote) {
        $SetStatusLog = Invoke-Command -Session $Session -ScriptBlock {
            Param($BCDEDITKey, $BCDEDITValue)
            bcdedit -set $BCDEDITKey $BCDEDITValue
        } -ArgumentList $BCDEDITKey, $BCDEDITValue
    } else {
        $SetStatusLog = Invoke-Command -ScriptBlock {
            Param($BCDEDITKey, $BCDEDITValue)
            bcdedit -set $BCDEDITKey $BCDEDITValue
        } -ArgumentList $BCDEDITKey, $BCDEDITValue
    }

    ($SetStatusLog -replace "\s{2,}", " ") | ForEach-Object {
        if ($_ -match "successfully") {
            $ReturnValue = $true
        }
    }

    return $ReturnValue
}

function UTGetBCDEDITValue
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$BCDEDITKey,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [string]$TargetPlaform = "current"
    )

    $ReturnValue = $null

    if ($Remote) {
        $GetStatusLog = Invoke-Command -Session $Session -ScriptBlock {
            Param($BCDEDITKey, $TargetPlaform)
            $CurrentFlag = $false
            $ReturnValue = $null
            bcdedit | ForEach-Object {
                if (($_ -match "identifier") -and ($_ -match $TargetPlaform)) {
                    $CurrentFlag = $true
                }

                if ($CurrentFlag) {
                    if ($_ -match $BCDEDITKey) {
                        $ReturnValue = $_
                    }
                }

                if ($_ -match "-------") {$CurrentFlag = $false}
            }

            return $ReturnValue
        } -ArgumentList $BCDEDITKey, $TargetPlaform
    } else {
        $GetStatusLog = Invoke-Command -ScriptBlock {
            Param($BCDEDITKey, $TargetPlaform)
            $CurrentFlag = $false
            $ReturnValue = $null
            bcdedit | ForEach-Object {
                if (($_ -match "identifier") -and ($_ -match $TargetPlaform)) {
                    $CurrentFlag = $true
                }

                if ($CurrentFlag) {
                    if ($_ -match $BCDEDITKey) {
                        $ReturnValue = $_
                    }
                }

                if ($_ -match "-------") {$CurrentFlag = $false}
            }

            return $ReturnValue
        } -ArgumentList $BCDEDITKey, $TargetPlaform
    }

    if (-not [String]::IsNullOrEmpty($GetStatusLog)) {
        $GetStatusLog = $GetStatusLog -replace "\s{2,}", " "
        $ReturnValue = $GetStatusLog.split(" ")[-1]
    }

    return $ReturnValue
}

# About debug mode
function UT-SetDebugMode
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$DebugMode,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $false

    $SetKey = "debug"
    if ($DebugMode) {
        $SetValue = "ON"
    } else {
        $SetValue = "OFF"
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $ReturnValue = UTSetBCDEDITValue `
            -BCDEDITKey $SetKey `
            -BCDEDITValue $SetValue `
            -Remote $Remote `
            -Session $Session
    } else {
        $LogKeyWord = "Host"
        $ReturnValue = UTSetBCDEDITValue `
            -BCDEDITKey $SetKey `
            -BCDEDITValue $SetValue `
            -Remote $Remote
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Set Debug mode as {1} is successful" -f $LogKeyWord, $DebugMode
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Set Debug mode as {1} is unsuccessful" -f $LogKeyWord, $DebugMode
        )
    }

    return $ReturnValue
}

function UT-CheckDebugMode
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$CheckFlag,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $true

    $DebugMode = $false
    $GetKey = "debug"
    $GetValue = $null

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $GetValue = UTGetBCDEDITValue `
            -BCDEDITKey $GetKey `
            -Remote $Remote `
            -Session $Session
    } else {
        $LogKeyWord = "Host"
        $GetValue = UTGetBCDEDITValue `
            -BCDEDITKey $GetKey `
            -Remote $Remote
    }

    Win-DebugTimestamp -output (
        "{0}: Check Debug mode as {1}" -f $LogKeyWord, $CheckFlag
    )

    if ([String]::IsNullOrEmpty($GetValue)) {
        if ($CheckFlag) {
            $ReturnValue = $false
        } else {
            $ReturnValue = $true
        }
    } else {
        if ($GetValue -eq "Yes") {
            $DebugMode = $true
        }

        if ($DebugMode -eq $CheckFlag) {
            $ReturnValue = $true
        } else {
            $ReturnValue = $false
        }
    }


    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Check Debug mode > passed" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Check Debug mode > failed, will be reset" -f $LogKeyWord
        )
    }

    return $ReturnValue
}

# About test mode
function UT-SetTestMode
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$TestMode,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $false

    $SetKey = "testsigning"
    if ($TestMode) {
        $SetValue = "ON"
    } else {
        $SetValue = "OFF"
    }

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $ReturnValue = UTSetBCDEDITValue `
            -BCDEDITKey $SetKey `
            -BCDEDITValue $SetValue `
            -Remote $Remote `
            -Session $Session
    } else {
        $LogKeyWord = "Host"
        $ReturnValue = UTSetBCDEDITValue `
            -BCDEDITKey $SetKey `
            -BCDEDITValue $SetValue `
            -Remote $Remote
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Set Test mode as {1} is successful" -f $LogKeyWord, $TestMode
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Set Test mode as {1} is unsuccessful" -f $LogKeyWord, $TestMode
        )
    }

    return $ReturnValue
}

function UT-CheckTestMode
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$CheckFlag,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $true

    $TestMode = $false
    $GetKey = "testsigning"
    $GetValue = $null

    if ($Remote) {
        $LogKeyWord = $Session.Name
        $GetValue = UTGetBCDEDITValue `
            -BCDEDITKey $GetKey `
            -Remote $Remote `
            -Session $Session
    } else {
        $LogKeyWord = "Host"
        $GetValue = UTGetBCDEDITValue `
            -BCDEDITKey $GetKey `
            -Remote $Remote
    }

    Win-DebugTimestamp -output (
        "{0}: Check Test mode as {1}" -f $LogKeyWord, $CheckFlag
    )

    if ([String]::IsNullOrEmpty($GetValue)) {
        $ReturnValue = $false
    } else {
        if ($GetValue -eq "Yes") {
            $TestMode = $true
        }

        if ($TestMode -eq $CheckFlag) {
            $ReturnValue = $true
        } else {
            $ReturnValue = $false
        }
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Check Test mode > passed" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Check Test mode > failed, will be reset" -f $LogKeyWord
        )
    }

    return $ReturnValue
}

# About UQ mode
function UT-SetUQMode
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$UQMode,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $true

    $regeditKey = "HKLM:\SYSTEM\CurrentControlSet\Services\icp_qat4\UQ"
    if ($UQMode) {
        $SetUQValue = 1
    } else {
        $SetUQValue = 0
    }

    $SetFlag = $false

    # Check: exist
    if ($Remote) {
        $LogKeyWord = $Session.Name
        $SetFlag = Invoke-Command -Session $Session -ScriptBlock {
            Param($regeditKey)
            if (Test-Path -Path $regeditKey) {
                return $true
            } else {
                return $false
            }
        } -ArgumentList $regeditKey
    } else {
        $LogKeyWord = "Host"
        if (Test-Path -Path $regeditKey) {
            $SetFlag = $true
        } else {
            $SetFlag = $false
        }
    }

    # Set UQ key value
    if ($SetFlag) {
        Win-DebugTimestamp -output (
            "{0}: Set UQ key as {1}, need to disable and enable qat devices" -f
                $LogKeyWord,
                $SetUQValue
        )

        if ($Remote) {
            Invoke-Command -Session $Session -ScriptBlock {
                Param($regeditKey, $SetUQValue)
                Set-ItemProperty $regeditKey -Name "EnableUQ" -Value $SetUQValue
            } -ArgumentList $regeditKey, $SetUQValue | out-null

            $ReturnValue = UT-CheckUQMode -CheckFlag $UQMode -Session $Session -Remote $Remote
        } else {
            Set-ItemProperty $regeditKey -Name "EnableUQ" -Value $SetUQValue | out-null
            $ReturnValue = UT-CheckUQMode -CheckFlag $UQMode -Remote $Remote
        }
    } else {
        Win-DebugTimestamp -output ("{0}: The UQ key is not exist, no need to set" -f $LogKeyWord)
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Set UQ mode as {1} is successful" -f $LogKeyWord, $UQMode
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Set UQ mode as {1} is unsuccessful" -f $LogKeyWord, $UQMode
        )
    }

    return $ReturnValue
}

function UT-CheckUQMode
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$CheckFlag,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $ReturnValue = $true

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    Win-DebugTimestamp -output (
        "{0}: Check UQ mode as {1}" -f $LogKeyWord, $CheckFlag
    )

    $regeditKey = "HKLM:\SYSTEM\CurrentControlSet\Services\icp_qat4\UQ"
    $GetFlag = $false

    # Check: exist
    if ($Remote) {
        $GetFlag = Invoke-Command -Session $Session -ScriptBlock {
            Param($regeditKey)
            if (Test-Path -Path $regeditKey) {
                return $true
            } else {
                return $false
            }
        } -ArgumentList $regeditKey
    } else {
        if (Test-Path -Path $regeditKey) {
            $GetFlag = $true
        } else {
            $GetFlag = $false
        }
    }

    # Get UQ key value and compare
    if ($GetFlag) {
        if ($Remote) {
            $UQModeInfo = Invoke-Command -Session $Session -ScriptBlock {
                Param($regeditKey)
                return (Get-ItemProperty $regeditKey).EnableUQ
            } -ArgumentList $regeditKey
        } else {
            $UQModeInfo = (Get-ItemProperty -Path $regeditKey).EnableUQ
        }

        if ($UQModeInfo -eq 1) {
            $UQMode = $true
        } else {
            $UQMode = $false
        }

        if ($UQMode -eq $CheckFlag) {
            $ReturnValue = $true
        } else {
            $ReturnValue = $false
        }
    } else {
        # The regedit key is null, return true and not changed
        $ReturnValue = $true
    }

    if ($ReturnValue) {
        Win-DebugTimestamp -output (
            "{0}: Check UQ mode > passed" -f $LogKeyWord
        )
    } else {
        Win-DebugTimestamp -output (
            "{0}: Check UQ mode > failed, will be reset" -f $LogKeyWord
        )
    }

    return $ReturnValue
}

#About FIPS
function UT-checkFIPSServicesData {
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

function UT-SetFIPSServicesData {
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
            "{0}: Set ServicesEnable as {1}, ServicesNeeded as {2}" -f
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

            $ReturnValue = UT-checkFIPSServicesData -CheckServiceEnableFlag "sym" -CheckServiceNeededFlag "sym" -Session $Session -Remote $Remote
        }
        else {
            Set-ItemProperty $regeditKey -Name "ServicesEnabled" -Value $ServiceEnable | out-null
            Set-ItemProperty $regeditKey -Name "ServicesNeeded" -Value $ServiceNeeded | out-null
            $ReturnValue = UT-checkFIPSServicesData -CheckServiceEnableFlag "sym" -CheckServiceNeededFlag "sym" -Remote $Remote
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

# About SSH
function UT-SetNoInheritance
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$FilePathName
    )

    # get current permissions
    $acl = Get-Acl -Path $FilePathName

    # disable inheritance
    $acl.SetAccessRuleProtection($true, $false)

    # set new permissions
    $acl | Set-Acl -Path $FilePathName

    Invoke-Command -ScriptBlock {
        Param($FilePathName)
        $localPath = (pwd).path
        $FilePath = Split-Path -Path $FilePathName
        $FileName = Split-Path -Path $FilePathName -Leaf
        cd $FilePath
        takeown /f $FileName
        cacls $FileName /P Administrator:F /E
        cd $localPath
    } -ArgumentList $FilePathName | out-null
}

function UT-CreateSSHKeys
{
    if (-not (Test-Path -Path $SSHKeys.Path)) {
        New-Item -Path $SSHKeys.Path -ItemType Directory | out-null
    }

    $LocalPrivateKey = "{0}\\{1}" -f $SSHKeys.Path, $SSHKeys.PrivateKeyName
    $LocalPublicKey = "{0}\\{1}" -f $SSHKeys.Path, $SSHKeys.PublicKeyName
    $LocalConfig = "{0}\\{1}" -f $SSHKeys.Path, $SSHKeys.ConfigName
    $ConfigInfo = "StrictHostKeyChecking no"
    $LocalKnownHost = "{0}\\{1}" -f $SSHKeys.Path, $SSHKeys.KnownHostName

    if (Test-Path -Path $LocalPrivateKey) {
        Remove-Item `
            -Path $LocalPrivateKey `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    if (Test-Path -Path $LocalPublicKey) {
        Remove-Item `
            -Path $LocalPublicKey `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    if (Test-Path -Path $LocalConfig) {
        Remove-Item `
            -Path $LocalConfig `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    if (Test-Path -Path $LocalKnownHost) {
        Remove-Item `
            -Path $LocalKnownHost `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    Win-DebugTimestamp -output (
        "Host: Create SSH config: {0}" -f $LocalConfig
    )
    $ConfigInfo | Out-File $LocalConfig -Append -Encoding ascii
    # disable inheritance
    UT-SetNoInheritance -FilePathName $LocalConfig | out-null

    Win-DebugTimestamp -output (
        "Host: Create SSH keys {0} and {1}" -f $LocalPrivateKey, $LocalPublicKey
    )
    Invoke-Command -ScriptBlock {
        Param($LocalPrivateKey)
        ssh-keygen -t "rsa" -f $LocalPrivateKey -P """"
    } -ArgumentList $LocalPrivateKey | out-null
}

# About Certificate
function UT-GetCertSubject
{
    Param(
        [string]$CertFile = $null
    )

    $ReturnValue = $null

    if ([String]::IsNullOrEmpty($CertFile)) {
        $CertFile = $Certificate.HostPF
    }

    $CertInfo = Invoke-Command -ScriptBlock {
        Param($CertFile)
        certutil -Dump $CertFile
    } -ArgumentList $CertFile

    $CertMessageFlag = $false
    ($CertInfo -replace "\s{2,}", "") | ForEach-Object {
        if ($CertMessageFlag) {
            $ReturnValue = $_.Split("=")[1]
            $CertMessageFlag = $false
        }

        if ($_ -match "Subject:") {
            $CertMessageFlag = $true
        }
    }

    return $ReturnValue
}

function UT-SetCertificate
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$CertFile,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    if ($Remote) {
        Invoke-Command -Session $Session -ScriptBlock {
            Param($CertFile)
            certutil -f -addstore TrustedPublisher $CertFile
            certutil -f -addstore root $CertFile
        } -ArgumentList $CertFile | out-null
    } else {
        Invoke-Command -ScriptBlock {
            Param($CertFile)
            certutil -f -addstore TrustedPublisher $CertFile
            certutil -f -addstore root $CertFile
        } -ArgumentList $CertFile | out-null
    }
}

function UT-DelCertificate
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$CertFile,

        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null
    )

    $CertSubject = UT-GetCertSubject -CertFile $CertFile

    if ($Remote) {
        Invoke-Command -Session $Session -ScriptBlock {
            Param($CertSubject)
            $CertFiles = Get-ChildItem -path Cert:\LocalMachine\root
            $CertFiles | ForEach-Object {
                if ($_.Subject -like ("*{0}*" -f $CertSubject)) {
                    $store = Get-Item $_.PSParentPath
                    $store.Open('ReadWrite')
                    $store.Remove($_)
                    $store.Close()
                }
            }

            $CertFiles = Get-ChildItem -path Cert:\LocalMachine\TrustedPublisher
            $CertFiles | ForEach-Object {
                if ($_.Subject -like ("*{0}*" -f $CertSubject)) {
                    $store = Get-Item $_.PSParentPath
                    $store.Open('ReadWrite')
                    $store.Remove($_)
                    $store.Close()
                }
            }
        } -ArgumentList $CertSubject | out-null
    } else {
        Invoke-Command -ScriptBlock {
            Param($CertFile)
            $CertFiles = Get-ChildItem -path Cert:\LocalMachine\root
            $CertFiles | ForEach-Object {
                if ($_.Subject -like ("*{0}*" -f $CertSubject)) {
                    $store = Get-Item $_.PSParentPath
                    $store.Open('ReadWrite')
                    $store.Remove($_)
                    $store.Close()
                }
            }

            $CertFiles = Get-ChildItem -path Cert:\LocalMachine\TrustedPublisher
            $CertFiles | ForEach-Object {
                if ($_.Subject -like ("*{0}*" -f $CertSubject)) {
                    $store = Get-Item $_.PSParentPath
                    $store.Open('ReadWrite')
                    $store.Remove($_)
                    $store.Close()
                }
            }
        } -ArgumentList $CertFile | out-null
    }
}

# About 7z
function UT-Use7z
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$InFile,

        [Parameter(Mandatory=$True)]
        [string]$OutFile
    )

    $ReturnValue = $false

    Import-Module $sevenZipDll
    $OutputLog = Start-SevenZipGzipDecompression -SourceFile $InFile `
                                                 -DestinationPath $OutFile `
                                                 -SevenZipPath $sevenZipExe

    Win-DebugTimestamp -output ("Host: Check output log of 7z tool")
    if ([String]::IsNullOrEmpty($OutputLog)) {
        Win-DebugTimestamp -output ("Host: Output log of 7z tool is null")
        $ReturnValue = $false
    } else {
        $CheckOutputFlag = WBase-CheckOutputLogError -OutputLog $OutputLog
        if ($CheckOutputFlag) {
            Win-DebugTimestamp -output ("Host: Use 7z tool is passed")
            $ReturnValue = $true
        } else {
            Win-DebugTimestamp -output ("Host: Error log of 7z tool > {0}" -f $OutputLog)
            $ReturnValue = $false
        }
    }

    Start-Sleep -Seconds 10

    return $ReturnValue
}

# WorkAround: 1. Check and set UQ mode by manual,
#                need disable and enable QAT devices to work well
#             2. if system version is greater than 25000,
#                need disable and enable QAT devices to work well
function UT-WorkAround
{
    Param(
        [Parameter(Mandatory=$True)]
        [bool]$Remote,

        [object]$Session = $null,

        [bool]$DisableFlag = $null
    )

    if ($Remote) {
        $LogKeyWord = $Session.Name
    } else {
        $LogKeyWord = "Host"
    }

    Win-DebugTimestamp -output ("{0}: Work around..." -f $LogKeyWord)

    if ($DisableFlag) {
        Win-DebugTimestamp -output (
            "{0}: Need to disable and enable qat device > Reset UQ mode" -f $LogKeyWord
        )
    }

    $DisableDeviceFlag = $DisableFlag

    <#
    $regeditKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\"

    if ($Remote) {
        $CurrentVersionInfo = Invoke-Command -Session $Session -ScriptBlock {
            Param($regeditKey)
            Get-ItemProperty $regeditKey
        } -ArgumentList $regeditKey
    } else {
        $CurrentVersionInfo = Get-ItemProperty $regeditKey
    }

    if ([int]($CurrentVersionInfo.CurrentBuildNumber) -gt 25000) {
        Win-DebugTimestamp -output (
            "{0}: Need to disable and enable qat device > {1}" -f
                $LogKeyWord,
                $CurrentVersionInfo.CurrentBuildNumber
        )

        $DisableDeviceFlag = $true
    }
    #>

    if ($DisableDeviceFlag) {
        if ($Remote) {
            WBase-EnableAndDisableQatDevice `
                -Remote $true `
                -Session $Session | out-null
        } else {
            WBase-EnableAndDisableQatDevice -Remote $false | out-null
        }
    }

    Win-DebugTimestamp -output ("{0}: Work around: End" -f $LogKeyWord)
}


Export-ModuleMember -Function *-*
