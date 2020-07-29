[CmdletBinding()]
param (
    [string]$config_file_path,
    [string]$google_backupandsync_root_dir
)



########## FUNCTIONS
function Quit ($exit_code = 0) {
    Write-Log '==> END OF LOG <=='
    $logpath = (Get-LoggingTarget File).Path
    Wait-Logging
    Remove-Module Logging -Force
    Write-Host "Log path: '$logpath'" -ForegroundColor Yellow
    if ($exit_code -ne 0) { notepad $logpath }
    exit $exit_code
}

function abspath ($parent = $pwd.Path) {
    ## convert to absolute path
    process {        
        if ([System.IO.Path]::IsPathRooted($_)) { $_ }
        else { Join-Path $parent $_ }
    }
}

function load_main_config {
    param (
        [string]$config_file_path,
        [string]$google_backupandsync_root_dir
    )

    if ($config_file_path) {
        $config_file_path = $config_file_path | abspath
    }
    else {
        $script_base_name = (gi $PSCommandPath).BaseName
        $config_file_path = Join-Path "$PSScriptRoot\conf" "$script_base_name`.yml"
    }

    Write-Log "Installing module: powershell-yaml"
    if (!(Get-Module powershell-yaml)) {
        if (!(Get-Module powershell-yaml -ListAvailable)) {
            Install-Module powershell-yaml -Force -Scope CurrentUser
        }
        Import-Module powershell-yaml -DisableNameChecking
    }

    Write-Log "Loading configuration from '$config_file_path'"
    $vars = (cat $config_file_path -Raw | ConvertFrom-Yaml).vars

    ## set config vars
    if (!(Test-Path $vars.acc_root_dir)) {
        if (!$google_backupandsync_root_dir) {
            $google_backupandsync_root_dir = $PSScriptRoot
            while ($google_backupandsync_root_dir -notlike "*\$($vars.acc_name)") {
                $google_backupandsync_root_dir = Split-Path $google_backupandsync_root_dir
                if (!$google_backupandsync_root_dir) {
                    Write-Log -Level ERROR -Message "Unable to determine Google Backup & Sync root directory"
                    Write-Log "Use parameter {google_backupandsync_root_dir} to specify"
                    Quit 1
                }
            }
        }
    }

    $vars.google_backupandsync_root_dir = $google_backupandsync_root_dir    
    $raw_config = cat $config_file_path
    $parsed_config = @()

    foreach ($line in $raw_config) {        
        $matched_placeholders = Select-String '\<(\w+)\>' -InputObject $line -AllMatches | % { $_.matches }

        foreach ($placeholder in $matched_placeholders.value) {
            $var_name = $placeholder.Trim('<>')
            if ($var_name -in $vars.keys) {
                $line = $line.Replace($placeholder, $vars.$var_name)
            }
        }

        $parsed_config += $line
    }

    $config = $parsed_config
    return $config
}



########## MAIN
$ErrorActionPreference = 'stop'
$script:start_time = Get-Date


### Init Logger
Write-Host "initializing logger" -ForegroundColor DarkGray
$log_file_name = (get-date $script:start_time -f 'yyyy-MM-ddTHH-mm-ss'), ((gi $PSCommandPath).BaseName + '.log') -join ('_')
$log_file_path = Join-Path (mkdir (Join-Path $HOME '.logs') -Force).FullName $log_file_name
if (!(Get-Module Logging)) {
    if (!(Get-Module Logging -ListAvailable)) {
        Install-Module Logging -Force -Scope CurrentUser
    }
    Import-Module Logging -DisableNameChecking
}
Add-LoggingTarget -Name Console -Configuration @{
    Level        = 'INFO'
    Format       = ' %{level}: %{message}'
    ColorMapping = @{DEBUG = 'BLUE'; INFO = 'White' ; WARNING = 'Yellow'; ERROR = 'Red' }
}
Add-LoggingTarget -Name File -Configuration @{
    Level  = 'DEBUG'
    Format = '[%{timestamp}] [%{filename:15}, ln.%{lineno:-3}] [%{level:7}] %{message}'
    Path   = $log_file_path
}
Write-Log -Level info 'Logger is up'


### Load main config
try {
    $CONFIG = load_main_config `
                -config_file_path:$config_file_path `
                -google_backupandsync_root_dir:$google_backupandsync_root_dir
}
catch {
    Write-Log -Level ERROR -Message $_.Exception.Message
    Write-Log -Level DEBUG -Message $_.InvocationInfo.PositionMessage
    Quit 1
}




### Remove logger and exit
Quit
