$OriginalForegroundColor = $Host.UI.RawUI.ForegroundColor
if ([System.Enum]::IsDefined([System.ConsoleColor], 1) -eq "False") { $OriginalForegroundColor = "Gray" }

$Global:GetChildItemColorVerticalSpace = 1

. "$PSScriptRoot\Get-ChildItemColorTable.ps1"

Function Get-FileColor($Item) {
    $Key = 'Default'

    If ([bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $Key = 'Symlink'
    } ElseIf ($Item.GetType().Name -eq 'DirectoryInfo') {
        $Key = 'Directory'
    } ElseIf ($Item.PSobject.Properties.Name -contains "Extension") {
        If ($GetChildItemColorTable.File.ContainsKey($Item.Extension)) {
            $Key = $Item.Extension
        }
    }

    $Color = $GetChildItemColorTable.File[$Key]
    Return $Color
}

Function Get-ChildItemColorFormatWide {
    Param(
        [string]$Path = "",
        [switch]$Force,
        [switch]$HideHeader,
        [switch]$TrailingSlashDirectory
    )

    $nnl = $True

    $Expression = "Get-ChildItem -Path `"$Path`" $Args"

    If ($Force) {$Expression += " -Force"}

    $Items = Invoke-Expression $Expression

    $lnStr = $Items | Select-Object Name | Sort-Object { LengthInBufferCells("$_") } -Descending | Select-Object -First 1
    $len = LengthInBufferCells($lnStr.Name)
    $width = $Host.UI.RawUI.WindowSize.Width
    $cols = If ($len) {[math]::Floor(($width + 1) / ($len + 2))} Else {1}
    if (!$cols) {$cols = 1}

    $i = 0
    $pad = [math]::Ceiling(($width + 2) / $cols) - 3

    ForEach ($Item in $Items) {
        If ($Item.PSobject.Properties.Name -contains "PSParentPath") {
            If ($Item.PSParentPath -match "FileSystem") {
                $ParentType = "Directory"
                $ParentName = $Item.PSParentPath.Replace("Microsoft.PowerShell.Core\FileSystem::", "")
            } ElseIf ($Item.PSParentPath -match "Registry") {
                $ParentType = "Hive"
                $ParentName = $Item.PSParentPath.Replace("Microsoft.PowerShell.Core\Registry::", "")
            }
        } Else {
            $ParentType = ""
            $ParentName = ""
            $LastParentName = $ParentName
        }

        If ($i -eq 0 -and $HideHeader) {
                Write-Host ""
        }

        # write header
        If ($LastParentName -ne $ParentName -and -not $HideHeader) {
            If ($i -ne 0 -AND $Host.UI.RawUI.CursorPosition.X -ne 0){  # conditionally add an empty line
                Write-Host ""
            }

            For ($l=1; $l -le $GetChildItemColorVerticalSpace; $l++) {
                Write-Host ""
            }

            Write-Host -Fore $OriginalForegroundColor "   $($ParentType):" -NoNewline

            $Color = $GetChildItemColorTable.File['Directory']
            Write-Host -Fore $Color " $ParentName"

            For ($l=1; $l -le $GetChildItemColorVerticalSpace; $l++) {
                Write-Host ""
            }
        }

        $nnl = ++$i % $cols -ne 0

        # truncate the item name
        $toWrite = $Item.Name

        If ($TrailingSlashDirectory -and $Item.GetType().Name -eq 'DirectoryInfo') {
            $toWrite += '\'
        }

        $itemLength = LengthInBufferCells($toWrite)
        If ($itemLength -gt $pad) {
            $toWrite = (CutString $toWrite $pad)
            $itemLength = LengthInBufferCells($toWrite)
        }

        $Color = Get-FileColor $Item
        $widePad = $pad - ($itemLength - $toWrite.Length)
        Write-Host ("{0,-$widePad}" -f $toWrite) -Fore $Color -NoNewLine:$nnl

        If ($nnl) {
            Write-Host "  " -NoNewLine
        }

        $LastParentName = $ParentName
    }

    For ($l=1; $l -lt $GetChildItemColorVerticalSpace; $l++) {
        Write-Host ""
    }

    If ($nnl) {  # conditionally add an empty line
        Write-Host ""
    }
}

Add-Type -assemblyname System.ServiceProcess

. "$PSScriptRoot\PSColorHelper.ps1"
. "$PSScriptRoot\FileInfo.ps1"
. "$PSScriptRoot\ServiceController.ps1"
. "$PSScriptRoot\MatchInfo.ps1"
. "$PSScriptRoot\ProcessInfo.ps1"

$Script:ShowHeader=$True

Function Out-ChildItemColor {
    [CmdletBinding(HelpUri='http://go.microsoft.com/fwlink/?LinkID=113362', RemotingCapability='None')]
    param(
        [switch] ${Transcript},
        [Parameter(Position=0, ValueFromPipeline=$True)]  [psobject]  ${InputObject}
    )

    Begin {
        Try {
            For ($l=1; $l -lt $GetChildItemColorVerticalSpace; $l++) {
                Write-Host ""
            }

            $outBuffer = $null
            If ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer)) {
                $PSBoundParameters['OutBuffer'] = 1
            }
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Core\Out-Default', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = {& $wrappedCmd @PSBoundParameters }

            $steppablePipeline = $scriptCmd.GetSteppablePipeline()
            $steppablePipeline.Begin($PSCmdlet)
        } Catch {
            Throw
        }
    }

    Process {
        Try {
            If (($_ -is [System.IO.DirectoryInfo]) -or ($_ -is [System.IO.FileInfo])) {
                FileInfo $_
                $_ = $Null
            }

            ElseIf ($_ -is [System.ServiceProcess.ServiceController]) {
                ServiceController $_
                $_ = $Null
            }

            ElseIf ($_ -is [Microsoft.Powershell.Commands.MatchInfo]) {
                MatchInfo $_
                $_ = $null
            }
            Else {
                $steppablePipeline.Process($_)
            }
        } Catch {
            Throw
        }
    }

    End {
        Try {
            For ($l=1; $l -le $GetChildItemColorVerticalSpace; $l++) {
                Write-Host ""
            }

            $Script:ShowHeader=$true
            $steppablePipeline.End()
        } Catch {
            Throw
        }
    }
    <#

    .ForwardHelpTargetName Out-Default
    .ForwardHelpCategory Function

    #>
}

Function Get-ChildItemColor {
[CmdletBinding(DefaultParameterSetName='Items', HelpUri='https://go.microsoft.com/fwlink/?LinkID=2096492')]
param(
    [Parameter(ParameterSetName='Items', Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [string[]]
    ${Path},

    [Parameter(ParameterSetName='LiteralItems', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias('PSPath','LP')]
    [string[]]
    ${LiteralPath},

    [Parameter(Position=1)]
    [string]
    ${Filter},

    [string[]]
    ${Include},

    [string[]]
    ${Exclude},

    [Alias('s')]
    [switch]
    ${Recurse},

    [uint]
    ${Depth},

    [switch]
    ${Force},

    [switch]
    ${Name})


dynamicparam
{
    try {
        $targetCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Management\Get-ChildItem', [System.Management.Automation.CommandTypes]::Cmdlet, $PSBoundParameters)
        $dynamicParams = @($targetCmd.Parameters.GetEnumerator() | Microsoft.PowerShell.Core\Where-Object { $_.Value.IsDynamic })
        if ($dynamicParams.Length -gt 0)
        {
            $paramDictionary = [Management.Automation.RuntimeDefinedParameterDictionary]::new()
            foreach ($param in $dynamicParams)
            {
                $param = $param.Value

                if(-not $MyInvocation.MyCommand.Parameters.ContainsKey($param.Name))
                {
                    $dynParam = [Management.Automation.RuntimeDefinedParameter]::new($param.Name, $param.ParameterType, $param.Attributes)
                    $paramDictionary.Add($param.Name, $dynParam)
                }
            }

            return $paramDictionary
        }
    } catch {
        throw
    }
}

begin
{
    try {
        $outBuffer = $null
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
        {
            $PSBoundParameters['OutBuffer'] = 1
        }

        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Management\Get-ChildItem', [System.Management.Automation.CommandTypes]::Cmdlet)
        $scriptCmd = {& $wrappedCmd @PSBoundParameters }

    } catch {
        throw
    }
}

process
{
    try {
        $items = $scriptCmd.invoke()

        If ($PSCmdlet.MyInvocation.Line -Match '\|') {  # pipeline is used
            $items
        } Else {
            $items | Out-ChildItemColor
        }
    } catch {
        throw
    }
}

end
{
    try {
    } catch {
        throw
    }
}
}
