param(
    [string] $ScriptPath = (
        Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'dist/codex-provider-setup.ps1'
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

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testRoot = Join-Path $projectRoot('.tmp/powershell-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$previousSkipMain = $env:CODEX_PROVIDER_SETUP_SKIP_MAIN
$previousCodexHome = $env:CODEX_HOME
$env:CODEX_PROVIDER_SETUP_SKIP_MAIN = '1'

try {
    if ($PSVersionTable.PSVersion.Major -le 5) {
        .([scriptblock]::Create((Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8)))
    } else {
        .$ScriptPath
    }

    Invoke-Test 'PowerShell syntax is valid' {
        $text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8
        $tokens = $null
        $errors = $null
        [void] [System.Management.Automation.Language.Parser]::ParseInput( $text, [ref] $tokens, [ref] $errors )
        Assert-Equal 0 $errors.Count 'Script contains parser errors'
    }

    Invoke-Test 'PowerShell message types own their colors' {
        $colors = @(
            $TYPE_STYLES.Values | ForEach-Object {
                $_.Color
            }
        )
        $uniqueColorCount = @($colors | Sort-Object -Unique).Count
        Assert-Equal $TYPE_STYLES.Count $uniqueColorCount 'Message type colors are not unique'
        Assert-Equal ([ConsoleColor]::Green) $TYPE_STYLES.Success.Color 'Success color differs'
        Assert-Equal ([ConsoleColor]::Yellow) $TYPE_STYLES.Warning.Color 'Warning color differs'
        Assert-Equal ([ConsoleColor]::Red) $TYPE_STYLES.Error.Color 'Error color differs'
        Assert-Equal ([ConsoleColor]::Magenta) $TYPE_STYLES.Title.Color 'Title color differs'
        Assert-Equal ([ConsoleColor]::Blue) $TYPE_STYLES.Ordered.Color 'Ordered type color differs'
        Assert-Equal ([ConsoleColor]::DarkMagenta) $TYPE_STYLES.Prompt.Color 'Prompt color differs'
        Assert-Equal ([ConsoleColor]::DarkCyan) $TYPE_STYLES.Change.Color 'Change color differs'
        Assert-True (
            -not (Get-Command Write-Message).Parameters.ContainsKey('Color')
        ) 'Message callers can override colors'
    }

    Invoke-Test 'Input and feedback UI enforce message or table parameter sets' {
        $inputSets = @((Get-Command Read-InputUI).ParameterSets.Name | Sort-Object)
        $feedbackSets = @((Get-Command Write-FeedbackUI).ParameterSets.Name | Sort-Object)
        Assert-Equal 'Message,Table'($inputSets -join ',') 'Input UI parameter sets differ'
        Assert-Equal 'Message,Table'($feedbackSets -join ',') 'Feedback UI parameter sets differ'
        foreach ($set in (Get-Command Read-InputUI).ParameterSets) {
            $prompt = @(
                $set.Parameters | Where-Object {
                    $_.Name -eq 'Prompt'
                }
            )[0]
            Assert-True $prompt.IsMandatory "Input UI prompt is optional in $($set.Name)"
        }
    }

    Invoke-Test 'Table and input styles reuse the message renderer' {
        foreach ($name in @( 'Write-Table', 'Write-Input' )) {
            $ast = (Get-Command $name).ScriptBlock.Ast
            $calls = @(
                $ast.FindAll(
                    {
                        param($node)

                        $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Message'
                    },
                    $true
                )
            )
            Assert-True ($calls.Count -gt 0) "$name does not reuse Write-Message"
        }
        $readInputAst = (Get-Command Read-Input).ScriptBlock.Ast
        $inputCalls = @(
            $readInputAst.FindAll(
                {
                    param($node)

                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Input'
                },
                $true
            )
        )
        Assert-True ($inputCalls.Count -gt 0) 'Read-Input does not reuse Write-Input'
    }

    Invoke-Test 'Only interaction UI owns block spacing' {
        foreach ($name in @( 'Read-InputUI', 'Write-FeedbackUI' )) {
            $ast = (Get-Command $name).ScriptBlock.Ast
            $calls = @(
                $ast.FindAll(
                    {
                        param($node)

                        $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-InteractionUI'
                    },
                    $true
                )
            )
            Assert-Equal 1 $calls.Count "$name does not own exactly one spacing boundary"
        }
        foreach ($name in @( 'Write-Message', 'Write-Table', 'Write-Input', 'Read-Input' )) {
            $ast = (Get-Command $name).ScriptBlock.Ast
            $calls = @(
                $ast.FindAll(
                    {
                        param($node)

                        $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-InteractionUI'
                    },
                    $true
                )
            )
            Assert-Equal 0 $calls.Count "$name must not manage interaction spacing"
        }
    }

    Invoke-Test 'Setup actions have unique keys and bound behavior' {
        $actions = Get-SetupActions
        Assert-Equal $actions.Count @($actions.Key | Select-Object -Unique).Count 'Setup action keys are duplicated'
        foreach ($action in $actions) {
            Assert-True ([bool] $action.Label) "Setup action $($action.Key) has no label"
            Assert-True ($action.Action -is [scriptblock]) "Setup action $($action.Key) has no behavior"
        }
        Assert-Equal '1,2,3,4,9'(@($actions.Key) -join ',') 'Setup action keys differ'
    }

    Invoke-Test 'Provider read-back ignores unrelated providers' {
        $caseRoot = Join-Path $testRoot 'managed-provider'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $script:ConfigPath = Join-Path $caseRoot 'config.toml'
        [IO.File]::WriteAllText(
            $script:ConfigPath,
            @(
                'model = "gpt-6-sol"',
                '',
                '[model_providers.keep]',
                'name = "Keep"',
                '',
                '[model_providers.provider_11111111]',
                'name = "Current"',
                'base_url = "https://current.example/v1"',
                '',
                '[model_providers.provider_11111111.headers]',
                'X-Custom = "1"'
            ) -join "`n",
            $utf8
        )
        $managed = Get-ProviderInfo @(Get-Content -LiteralPath $script:ConfigPath -Encoding UTF8) 'provider_11111111'
        Assert-True $managed.Present 'Managed provider was not detected'
        Assert-True (-not $managed.Recognizable) 'A provider section with subtables must not be removable'
        Assert-Equal 'Current' $managed.ProviderName 'Managed provider name differs'
        Assert-Equal 'https://current.example/v1' $managed.BaseUrl 'Managed Base URL differs'
        [IO.File]::WriteAllText(
            $script:ConfigPath,
            @( '[model_providers.provider_11111111]', 'wire_api = "responses"' ) -join "`n",
            $utf8
        )
        $unnamed = Get-ProviderInfo @(Get-Content -LiteralPath $script:ConfigPath -Encoding UTF8) 'provider_11111111'
        Assert-True $unnamed.Present 'A managed section without a name was not detected'
        [IO.File]::WriteAllText( $script:ConfigPath, 'model = "gpt-6-sol"', $utf8 )
        $absent = Get-ProviderInfo @(Get-Content -LiteralPath $script:ConfigPath -Encoding UTF8) 'provider_11111111'
        Assert-True (-not $absent.Present) 'A config without the managed section reported a provider'
    }
    Invoke-Test 'Selection rewrite keeps provider sections' {
        $lines = @(
            'approval_policy = "never"',
            'model = "old-model"',
            '',
            '[model_providers.keep]',
            'name = "Keep"',
            '',
            '[model_providers.provider_orphan]',
            'name = "Orphan"',
            '',
            '[model_providers.provider_orphan.headers]',
            'X-Token = "secret"'
        )
        $selection = New-SetupSelection 'Next' 'https://next.example/v1' 'next-model' '' $null
        $content = New-SelectedConfigContent $lines $selection 'provider_22222222'
        Assert-True ($content -match '\[model_providers\.provider_orphan\]') 'Existing provider was removed'
        Assert-True ($content -match 'model_provider = "provider_22222222"') 'Selection was not rewritten'
    }

    Invoke-Test 'Codex strict config accepts OpenAI and custom output' {
        $codexCommand = Get-Command codex.cmd -ErrorAction SilentlyContinue
        if (-not $codexCommand) {
            Write-Warning 'codex.cmd is unavailable; strict client validation was skipped.'
            return
        }

        $caseRoot = Join-Path $testRoot 'strict-config'
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $env:CODEX_HOME = $caseRoot
        $script:CodexHomeDir = $caseRoot
        $script:ConfigPath = Join-Path $caseRoot 'config.toml'
        $script:BackupDir = Join-Path $caseRoot $BACKUP_DIRNAME
        $script:BackupConfig = Join-Path $script:BackupDir 'config.toml'
        $script:ManifestPath = Join-Path $script:BackupDir 'manifest.txt'
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        $openAI = New-SetupSelection 'OpenAI' 'https://api.openai.com/v1' 'gpt-6-sol' 'medium'([Nullable[int]] 272000)
        $content = New-SelectedConfigContent @() $openAI 'provider_11111111'
        $content = Add-ProviderSection $content 'provider_11111111' $openAI 'test-key'
        [System.IO.File]::WriteAllText( $script:ConfigPath, $content, $utf8NoBom )
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $openAIOutput = ('' | & $codexCommand.Source app-server --strict-config --stdio 2>&1| Out-String)
            Assert-Equal 0 $LASTEXITCODE "Codex rejected OpenAI config: $openAIOutput"

            $custom = New-SetupSelection 'Local provider'(Resolve-BaseUrl '0.0.0.0/v1') 'local-model' '' $null
            $content = New-SelectedConfigContent @(
                Get-Content -LiteralPath $script:ConfigPath -Encoding UTF8
            ) $custom 'provider_22222222'
            $content = Add-ProviderSection $content 'provider_22222222' $custom 'test-key'
            [System.IO.File]::WriteAllText( $script:ConfigPath, $content, $utf8NoBom )
            $customOutput = ('' | & $codexCommand.Source app-server --strict-config --stdio 2>&1| Out-String)
            Assert-Equal 0 $LASTEXITCODE "Codex rejected custom config: $customOutput"
            Assert-True (
                $content -match '(?m)^base_url = "http://0\.0\.0\.0/v1"$'
            ) 'Normalized local Base URL is missing'
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
} finally {
    $env:CODEX_PROVIDER_SETUP_SKIP_MAIN = $previousSkipMain
    $env:CODEX_HOME = $previousCodexHome
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host ''
Write-Host "PowerShell-specific checks: $($script:Passed) passed; $($script:Failed) failed"
if ($script:Failed -gt 0) {
    exit 1
}
