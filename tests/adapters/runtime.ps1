param(
    [Parameter(Mandatory = $true)] [string] $Action,
    [Parameter(Mandatory = $true)] [string] $ScriptPath,
    [string] $InputPath = '',
    [string] $OutputPath = '',
    [string] $ProviderName = '',
    [string] $BaseUrl = '',
    [string] $Model = '',
    [string] $ReasoningEffort = '',
    [string] $ContextWindow = '',
    [string] $ApiKey = '',
    [string] $ProviderId = 'codex_provider_setup_1',
    [string] $Value = '',
    [string] $CodexHome = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$env:CODEX_PROVIDER_SETUP_SKIP_MAIN = '1'
.$ScriptPath

switch ($Action) {
    'transform' {
        $lines = if ((Get-Item -LiteralPath $InputPath).Length -eq 0) {
            @()
        } else {
            @(Get-Content -LiteralPath $InputPath -Encoding UTF8)
        }
        $context = if ($ContextWindow) {
            [Nullable[int]] [int] $ContextWindow
        } else {
            $null
        }
        $selection = New-SetupSelection $ProviderName $BaseUrl $Model $ReasoningEffort $context
        $content = New-SelectedConfigContent $lines $selection $ProviderId
        $content = Add-ProviderSection $content $ProviderId $selection $ApiKey
        Assert-GeneratedConfig $content $ProviderId
        [IO.File]::WriteAllText( $OutputPath, $content, (New-Object System.Text.UTF8Encoding($false)) )
    }
    'resolve-base-url' {
        $resolved = Resolve-BaseUrl $Value 6>$null
        [Console]::Out.Write($resolved)
    }
    'ui-layout' {
        $script:HasInteractionUI = $false
        Write-FeedbackUI -MessageContent 'Notice' -MessageType 'Info'
        Write-FeedbackUI -TableTitle 'Summary' -TableItems @('Name: Value') -TableTypes @('Info') -TableKind 'Unordered'
        Write-FeedbackUI -TableTitle 'Changes' -TableItems @('Changed') -TableTypes @('Change') -TableKind 'Unordered'
        Write-FeedbackUI -TableTitle 'Menu' -TableItems @( 'First', 'Second' ) -TableTypes @(
            '1',
            '2'
        ) -TableKind 'Ordered'
    }
    'message-types' {
        foreach ($type in @( 'Info', 'Detail', 'Success', 'Warning', 'Error', 'Prompt', 'Change', '7' )) {
            Write-Message -Content $type -Type $type
        }
        $rejected = $false
        try {
            Write-Message -Content 'Invalid' -Type 'Arbitrary'
        } catch {
            $rejected = $true
        }
        if (-not $rejected) {
            throw 'Unknown message type was accepted'
        }
        [Console]::Out.Write('INVALID=REJECTED')
    }
    'choice' {
        function Read-Host {
            param(
                [string] $Prompt,
                [switch] $AsSecureString
            )

            return '2'
        }

        $script:HasInteractionUI = $false
        $choice = Read-Choice 'Choose' @( '1', '2' ) @( 'First', 'Second' ) 'Select'
        [Console]::Out.Write("RESULT=$choice")
    }
    'default-input' {
        function Read-Host {
            param(
                [string] $Prompt,
                [switch] $AsSecureString
            )

            return ''
        }

        $script:HasInteractionUI = $false
        $value = Read-ValueWithDefault 'Base URL' 'Enter Base URL' 'https://api.example/v1'
        [Console]::Out.Write("RESULT=$value")
    }
    'messages' {
        [Console]::Out.WriteLine((Get-Message 'ConfigUpdated' 'config.toml'))
        [Console]::Out.Write((Get-Message 'ConfigWriteFailed' @( 'backup', 'write failed' )))
    }
    'configure' {
        $script:CodexHomeDir = $CodexHome
        $script:ConfigPath = Join-Path $CodexHome 'config.toml'
        $script:BackupDir = Join-Path $CodexHome $BACKUP_DIRNAME
        $script:BackupConfig = Join-Path $script:BackupDir 'config.toml'
        $script:ManifestPath = Join-Path $script:BackupDir 'manifest.txt'

        function Read-ApiKey {
            return $ApiKey
        }

        function Read-Choice {
            if ($env:CODEX_PROVIDER_SETUP_TEST_CONFIRM) {
                return $env:CODEX_PROVIDER_SETUP_TEST_CONFIRM
            }
            return '1'
        }

        $context = if ($ContextWindow) {
            [Nullable[int]] [int] $ContextWindow
        } else {
            $null
        }
        $selection = New-SetupSelection $ProviderName $BaseUrl $Model $ReasoningEffort $context
        Invoke-Configure $selection
    }
    'switch-provider' {
        $script:CodexHomeDir = $CodexHome
        $script:ConfigPath = Join-Path $CodexHome 'config.toml'
        $script:BackupDir = Join-Path $CodexHome $BACKUP_DIRNAME
        $script:BackupConfig = Join-Path $script:BackupDir 'config.toml'
        $script:ManifestPath = Join-Path $script:BackupDir 'manifest.txt'

        function Read-Choice {
            if ($env:CODEX_PROVIDER_SETUP_TEST_CONFIRM) {
                return $env:CODEX_PROVIDER_SETUP_TEST_CONFIRM
            }
            return '1'
        }

        Invoke-SwitchProvider
    }
    'remove-provider' {
        $script:CodexHomeDir = $CodexHome
        $script:ConfigPath = Join-Path $CodexHome 'config.toml'
        $script:BackupDir = Join-Path $CodexHome $BACKUP_DIRNAME
        $script:BackupConfig = Join-Path $script:BackupDir 'config.toml'
        $script:ManifestPath = Join-Path $script:BackupDir 'manifest.txt'
        $script:RemoveChoiceRead = $false

        function Read-Choice {
            if ($script:RemoveChoiceRead) {
                return '1'
            }
            $script:RemoveChoiceRead = $true
            return $(
                if ($env:CODEX_PROVIDER_SETUP_TEST_CONFIRM) {
                    $env:CODEX_PROVIDER_SETUP_TEST_CONFIRM
                } else {
                    '1'
                }
            )
        }

        Invoke-RemoveProvider
    }
    'restore' {
        $script:CodexHomeDir = $CodexHome
        $script:ConfigPath = Join-Path $CodexHome 'config.toml'
        $script:BackupDir = Join-Path $CodexHome $BACKUP_DIRNAME
        $script:BackupConfig = Join-Path $script:BackupDir 'config.toml'
        $script:ManifestPath = Join-Path $script:BackupDir 'manifest.txt'

        function Read-Choice {
            return '1'
        }

        Invoke-Restore
    }
    'menu-items' {
        $actions = Get-SetupActions
        $lines = @(
            $actions | ForEach-Object {
                "$($_.Key)`t$($_.Label)"
            }
        )
        [Console]::Out.Write(($lines -join "`n"))
    }
    default {
        throw "Unknown adapter action: $Action"
    }
}
