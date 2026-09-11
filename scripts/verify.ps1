$ErrorActionPreference = 'Stop'

function Invoke-Check {
    param([string] $Command, [string[]] $Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

Push-Location (Join-Path $PSScriptRoot '..')
try {
    Invoke-Check 'rojo' @('sourcemap', 'test.project.json', '--output', 'sourcemap.json')
    Invoke-Check 'lune' @('run', 'scripts/tests/run.luau')
    Invoke-Check 'selene' @('src', 'tests')
    Invoke-Check 'stylua' @('--check', '.')
    Invoke-Check 'luau-lsp' @(
        'analyze', '--sourcemap=sourcemap.json', '--defs=types/globalTypes.d.luau',
        '--ignore=**/Packages/**', '--ignore=**/ServerPackages/**', '--ignore=**/DevPackages/**',
        'src', 'tests'
    )
    New-Item -ItemType Directory -Path 'build' -Force | Out-Null
    Invoke-Check 'rojo' @('build', 'default.project.json', '--output', 'build/game.rbxl')
    Invoke-Check 'rojo' @('build', 'test.project.json', '--output', 'build/test.rbxl')
    Write-Host 'Local checks passed. Run build/test.rbxl in Studio for runtime checks.'
} finally {
    Pop-Location
}
