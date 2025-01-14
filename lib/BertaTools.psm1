
function Berta-ENVInit
{
    <#
    # Copy Test path
    if (Test-Path -Path $BertaENVInit.QATTest.DestinationPath) {
        Remove-Item `
            -Path $BertaENVInit.QATTest.DestinationPath `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop
    }

    $QATTestPathLocal = Split-Path -Parent $BertaENVInit.QATTest.DestinationPath
    Copy-Item `
        -Path $BertaENVInit.QATTest.SourcePath `
        -Destination $QATTestPathLocal `
        -Recurse `
        -Force `
        -Confirm:$false `
        -ErrorAction Stop
    #>

    # Update Powershell profile
    $ProFileFullPathSource = "{0}\\{1}" -f
        $BertaENVInit.PSProFile.SourcePath,
        $BertaENVInit.PSProFile.FileName
    Foreach ($DestinationPath in $BertaENVInit.PSProFile.DestinationPath) {
        Foreach ($DestinationChildPath in $BertaENVInit.PSProFile.DestinationChildPath) {
            $ProFilePath = "{0}\\{1}" -f
                $DestinationPath,
                $DestinationChildPath
            $ProFileFullPath = "{0}\\{1}" -f
                $ProFilePath,
                $BertaENVInit.PSProFile.FileName
            $CopyFlag = $false

            if (-not (Test-Path -Path $ProFilePath)) {
                New-Item -Path $ProFilePath -ItemType Directory | out-null
            }

            if (Test-Path -Path $ProFileFullPath) {
                $SourceMD5 = (certutil -hashfile $ProFileFullPathSource MD5)[1]
                $DestinationMD5 = (certutil -hashfile $ProFileFullPath MD5)[1]
                if ($SourceMD5 -ne $DestinationMD5) {
                    $CopyFlag = $true
                    Remove-Item `
                        -Path $ProFileFullPath `
                        -Force `
                        -Confirm:$false `
                        -ErrorAction Stop
                }
            } else {
                $CopyFlag = $true
            }

            if ($CopyFlag) {
                Copy-Item `
                    -Path $ProFileFullPathSource `
                    -Destination $ProFileFullPath `
                    -Force `
                    -Confirm:$false `
                    -ErrorAction Stop
            }
        }
    }
}

function Berta-CopyTestDir
{
    $ReturnValue = $true

    $LocalTestDir = "C:\QAT-Windows-Test"

    try {
        $LocalIPProxy = "http://child-prc.intel.com:913"
        $RemoteTestDir = "https://github.com/cuiyanx/QAT-Windows-Test.git"

        Invoke-Command -ScriptBlock {
            Param($LocalTestDir, $LocalIPProxy, $RemoteTestDir)
            CD C:\

            if (-not (Test-Path -Path "C:\.git")) {
                git init
            }

            git config --global --unset http.proxy
            git config --global --unset https.proxy

            git config --global http.proxy $LocalIPProxy
            git config --global https.proxy $LocalIPProxy

            if (Test-Path -Path $LocalTestDir) {
                CD $LocalTestDir
                git checkout . 2>&1 | out-null
                git pull $RemoteTestDir main 2>&1 | out-null
            } else {
                git clone $RemoteTestDir $LocalTestDir 2>&1 | out-null
            }
        } -ArgumentList $LocalTestDir, $LocalIPProxy, $RemoteTestDir | out-null
    } catch {
        Win-DebugTimestamp -output ("Git Error: {0}" -f $_)
        Win-DebugTimestamp -output ("Git repo has been failed, change to copy test dir from backup path")

        $RemoteTestDir = "{0}\\*" -f $BertaENVInit.TestScriptPath
        Copy-Item `
            -Path $RemoteTestDir `
            -Destination $LocalTestDir `
            -Recurse `
            -Force `
            -Confirm:$false `
            -ErrorAction Stop | out-null
    }

    if (-not (Test-Path -Path $LocalTestDir)) {
        $ReturnValue = $false
    }

    return $ReturnValue
}

function Berta-UpdateMainFiles
{
    $ReturnValue = $false

    ForEach ($SourceFile in $BertaENVInit.BertaClient.SourceFiles) {
        $BertaSource = "{0}\\{1}" -f
            $BertaENVInit.BertaClient.SourcePath,
            $SourceFile
        $BertaDestination = "{0}\\{1}" -f
            $BertaENVInit.BertaClient.DestinationPath,
            $SourceFile

        $SourceMD5 = (certutil -hashfile $BertaSource MD5).split("\n")[1]
        if (Test-Path -Path $BertaDestination) {
            $DestinationMD5 = (certutil -hashfile $BertaDestination MD5).split("\n")[1]
        } else {
            $DestinationMD5 = 0
        }

        if ($SourceMD5 -ne $DestinationMD5) {
            $ReturnValue = $true
            Copy-Item `
                -Path $BertaSource `
                -Destination $BertaDestination `
                -Force `
                -ErrorAction Stop | out-null
        }
    }

    return $ReturnValue
}

function Berta-QatDriverCheck
{
    $CheckList = WBase-CheckDriverInstalled -Remote $false

    return $CheckList
}

function Berta-QatDriverInstall
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$DriverPath,

        [Parameter(Mandatory=$True)]
        [bool]$HVMode,

        [Parameter(Mandatory=$True)]
        [bool]$UQMode
    )

    $LocationInfo.HVMode = $HVMode
    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $DriverPath
    $PFDriverExe = WBase-PFDriverPathInit -PFDriverFullPath $PFVFDriverPath.PF
    WBase-InstallAndUninstallQatDriver -SetupExePath $PFDriverExe `
                                       -Operation $true `
                                       -Remote $false `
                                       -UQMode $UQMode

    return $PsReturnCode.Success
}

function Berta-QatDriverUnInstall
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$DriverPath
    )

    # Remove child vm's
    $VMList = Get-VM
    if (-not [String]::IsNullOrEmpty($VMList)) {
        Foreach ($VM in $VMList) {
            HV-RemoveVM -VMName $VM.Name | out-null
        }
    }

    $PFVFDriverPath = WBase-GetDriverPath -BuildPath $DriverPath
    $PFDriverExe = WBase-PFDriverPathInit -PFDriverFullPath $PFVFDriverPath.PF
    WBase-InstallAndUninstallQatDriver -SetupExePath $PFDriverExe `
                                       -Operation $false `
                                       -Remote $false

    return $PsReturnCode.Success
}

function Berta-CompressReturnFiles
{
    Param(
        [Parameter(Mandatory=$True)]
        [string]$Path,

        [int]$Threshold = 500KB
    )

    $IgnoreList = @(
        "agent_log.txt",
        "job_2_log.txt",
        "STVTest-ps.log",
        "result.log",
        "result.csv",
        "results-log.txt"
    )

    try {
        $Files = Get-ChildItem -Path $Path -Exclude $IgnoreList -Recurse -ErrorAction Stop |
            Where-Object {$_.Extension -ne ".zip"}

        foreach ($file in $Files) {
            if ($file.Length -gt $Threshold) {
                $ZipName = "{0}\{1}.zip" -f $file.DirectoryName, $file.BaseName
                Win-DebugTimestamp -output (
                    "{0} is greater than {1}; Compressing to {2} and removing original." -f
                        $file.Name,
                        $Threshold,
                        $ZipName
                )

                Compress-Archive `
                    -LiteralPath ($file.FullName) `
                    -DestinationPath $ZipName `
                    -CompressionLevel Optimal `
                    -Force `
                    -ErrorAction Stop

                Remove-Item -Path $file -Force -Confirm:$false -ErrorAction Stop
            }
        }
    } catch {
        throw ("Error: Compress return file is failed > {0}" -f $file)
    }
}


Export-ModuleMember -Function *-*
