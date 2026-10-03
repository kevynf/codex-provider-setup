param(
    [string] $ScriptPath = (
        Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'dist/claude-provider-setup.ps1'
    )
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param(
        [bool] $Condition,
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string] $Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message (expected: $Expected; actual: $Actual)"
    }
}

function Invoke-Test {
    param(
        [string] $Name,
        [scriptblock] $Body
    )

    try {
        & $Body
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    } catch {
        Write-Host "[FAIL] $Name`n  $($_.Exception.Message)" -ForegroundColor Red
        $script:Failed++
    }
}

function Get-ClaudeSettings {
    param([string] $Root)

    return Get-Content -LiteralPath (Join-Path $Root 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Invoke-ClaudeConfigure {
    param([string] $Root)

    $previousConfigDir = $env:CLAUDE_CONFIG_DIR
    $previousSkipMain = $env:CLAUDE_PROVIDER_SETUP_SKIP_MAIN
    $global:ClaudeAnswers = [System.Collections.Generic.Queue[string]]::new()
    foreach ($answer in @( 'Proxy', 'https://proxy.example/v1', 'third-party-model', 'test-token' )) {
        $global:ClaudeAnswers.Enqueue($answer)
    }

    function global:Read-Host {
        param(
            [string] $Prompt,
            [switch] $AsSecureString
        )

        $value = $global:ClaudeAnswers.Dequeue()
        if ($AsSecureString) {
            $secure = New-Object System.Security.SecureString
            foreach ($character in $value.ToCharArray()) {
                $secure.AppendChar($character)
            }
            $secure.MakeReadOnly()
            return $secure
        }
        return $value
    }

    try {
        $env:CLAUDE_CONFIG_DIR = $Root
        $env:CLAUDE_PROVIDER_SETUP_SKIP_MAIN = '0'
        & $ScriptPath configure | Out-Null
    } finally {
        Remove-Item function:\global:Read-Host -ErrorAction SilentlyContinue
        Remove-Variable ClaudeAnswers -Scope Global -ErrorAction SilentlyContinue
        if ($null -eq $previousConfigDir) {
            Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
        } else {
            $env:CLAUDE_CONFIG_DIR = $previousConfigDir
        }
        if ($null -eq $previousSkipMain) {
            Remove-Item Env:CLAUDE_PROVIDER_SETUP_SKIP_MAIN -ErrorAction SilentlyContinue
        } else {
            $env:CLAUDE_PROVIDER_SETUP_SKIP_MAIN = $previousSkipMain
        }
    }
}

function Invoke-ClaudeRestore {
    param([string] $Root)

    $previousConfigDir = $env:CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR = $Root
        & $ScriptPath restore | Out-Null
    } finally {
        if ($null -eq $previousConfigDir) {
            Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
        } else {
            $env:CLAUDE_CONFIG_DIR = $previousConfigDir
        }
    }
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testRoot = Join-Path $projectRoot('.tmp/claude-powershell-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

try {
    Invoke-Test 'Claude Code PowerShell syntax is valid' {
        $text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8
        $tokens = $null
        $errors = $null
        [void] [System.Management.Automation.Language.Parser]::ParseInput( $text, [ref] $tokens, [ref] $errors )
        Assert-Equal 0 $errors.Count 'Script contains parser errors'
    }

    Invoke-Test 'Claude Code creates third-party settings without an original file' {
        $caseRoot = Join-Path $testRoot 'new-settings'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        Invoke-ClaudeConfigure $caseRoot
        $settings = Get-ClaudeSettings $caseRoot
        foreach (
            $name in @(
                'ANTHROPIC_MODEL',
                'ANTHROPIC_DEFAULT_OPUS_MODEL',
                'ANTHROPIC_DEFAULT_SONNET_MODEL',
                'ANTHROPIC_DEFAULT_HAIKU_MODEL'
            )
        ) {
            Assert-Equal 'third-party-model' $settings.env.($name) "$name was not initialized"
        }
        Assert-Equal '1' $settings.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 'Traffic flag is missing'
        Assert-True (
            (Get-Content -LiteralPath (Join-Path $caseRoot '.provider-backup/manifest.txt') -Raw) -match
            '(?m)^original_settings_existed=0\r?$'
        ) 'Manifest incorrectly reported an original settings file'
    }

    Invoke-Test 'Claude Code preserves mappings and restores the original settings' {
        $caseRoot = Join-Path $testRoot 'existing-settings'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $original = '{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"opus-x","ANTHROPIC_DEFAULT_SONNET_MODEL":"sonnet-x","ANTHROPIC_DEFAULT_HAIKU_MODEL":"haiku-x","CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1","KEEP":"yes"},"permissions":{"defaultMode":"acceptEdits"}}'
        [IO.File]::WriteAllText(
            (Join-Path $caseRoot 'settings.json'),
            $original,
            (New-Object System.Text.UTF8Encoding($false))
        )
        Invoke-ClaudeConfigure $caseRoot
        $settings = Get-ClaudeSettings $caseRoot
        $envPropertyNames = @()
        foreach ($property in $settings.env.PSObject.Properties) {
            $envPropertyNames += $property.Name
        }
        Assert-True ('ANTHROPIC_MODEL' -notin $envPropertyNames) 'Existing mappings were overridden'
        Assert-Equal 'sonnet-x' $settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL 'Existing mapping changed'
        Assert-Equal 'yes' $settings.env.KEEP 'Existing env setting changed'
        Assert-Equal 'acceptEdits' $settings.permissions.defaultMode 'Unrelated setting changed'
        Assert-Equal $original(
            [IO.File]::ReadAllText((Join-Path $caseRoot '.provider-backup/settings.json'))
        ) 'Backup did not preserve the original settings'
        Invoke-ClaudeRestore $caseRoot
        Assert-Equal $original(
            [IO.File]::ReadAllText((Join-Path $caseRoot 'settings.json'))
        ) 'Restore did not recover the original settings'
        Assert-True (
            -not (Test-Path -LiteralPath (Join-Path $caseRoot '.provider-backup'))
        ) 'Restore left the backup directory'
    }

    Invoke-Test 'Claude Code rejects invalid JSON without overwriting it' {
        $caseRoot = Join-Path $testRoot 'invalid-json'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $invalid = '{invalid'
        [IO.File]::WriteAllText(
            (Join-Path $caseRoot 'settings.json'),
            $invalid,
            (New-Object System.Text.UTF8Encoding($false))
        )
        $failed = $false
        try {
            Invoke-ClaudeConfigure $caseRoot
        } catch {
            $failed = $true
        }
        Assert-True $failed 'Invalid JSON was accepted'
        Assert-Equal $invalid(
            [IO.File]::ReadAllText((Join-Path $caseRoot 'settings.json'))
        ) 'Invalid JSON was overwritten'
    }
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host ''
Write-Host "Claude Code PowerShell tests: $($script:Passed) passed; $($script:Failed) failed"
if ($script:Failed -gt 0) {
    exit 1
}
