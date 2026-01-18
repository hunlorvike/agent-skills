<#
.SYNOPSIS
    Analyzes EF Core usage for common performance issues.

.DESCRIPTION
    Scans C# files for potential EF Core anti-patterns including:
    - N+1 query patterns
    - Missing AsNoTracking
    - Sync over async
    - ToList before filtering

.PARAMETER Path
    The path to the project to analyze.

.PARAMETER OutputFormat
    Output format: 'console', 'json', or 'markdown'.

.EXAMPLE
    .\analyze-efcore-queries.ps1 -Path "C:\Projects\MyApi" -OutputFormat "console"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet("console", "json", "markdown")]
    [string]$OutputFormat = "console"
)

$ErrorActionPreference = "Stop"
$script:Issues = @()

function Add-Issue {
    param(
        [string]$File,
        [int]$Line,
        [string]$Rule,
        [string]$Message,
        [ValidateSet("Critical", "High", "Medium", "Low")]
        [string]$Severity
    )

    $script:Issues += [PSCustomObject]@{
        File     = $File
        Line     = $Line
        Rule     = $Rule
        Message  = $Message
        Severity = $Severity
    }
}

function Get-DataFiles {
    param([string]$BasePath)

    Get-ChildItem -Path $BasePath -Filter "*.cs" -Recurse |
    Where-Object { 
        $_.FullName -notmatch "\\(bin|obj|node_modules|Migrations)\\" -and
        $_.FullName -notmatch "\.Designer\.cs$"
    }
}

function Test-ToListBeforeFilter {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for ToList/ToArray followed by Where/Select
        if ($line -match "\.ToList(Async)?\s*\(\s*\)\s*\.\s*(Where|Select|OrderBy|First|Single)") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE001" `
                -Message "Calling ToList() before filtering loads all records into memory. Apply filters before materialization." `
                -Severity "Critical"
        }

        if ($line -match "\.ToArray(Async)?\s*\(\s*\)\s*\.\s*(Where|Select|OrderBy)") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE001" `
                -Message "Calling ToArray() before filtering loads all records into memory. Apply filters before materialization." `
                -Severity "Critical"
        }
    }
}

function Test-MissingAsNoTracking {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath -Raw

    # Look for query patterns without AsNoTracking
    if ($content -match "context\.\w+\s*\.\s*Where" -or 
        $content -match "_context\.\w+\s*\.\s*Where" -or
        $content -match "context\.\w+\s*\.\s*Select" -or
        $content -match "_context\.\w+\s*\.\s*Select") {
        
        # Check if AsNoTracking is used anywhere in the file
        if ($content -notmatch "AsNoTracking") {
            $lines = Get-Content -Path $FilePath
            $lineNumber = 0
            foreach ($line in $lines) {
                $lineNumber++
                if ($line -match "context\.\w+\s*\.\s*(Where|Select|Include)" -and 
                    $line -notmatch "AsNoTracking") {
                    Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE002" `
                        -Message "Consider using AsNoTracking() for read-only queries to improve performance." `
                        -Severity "Medium"
                    break  # Only report once per file
                }
            }
        }
    }
}

function Test-SyncOverAsync {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for .Result
        if ($line -match "\.Result\b" -and $line -match "(context|_context)") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE003" `
                -Message "Using .Result blocks the thread. Use 'await' with async methods instead." `
                -Severity "Critical"
        }

        # Check for .Wait()
        if ($line -match "\.Wait\s*\(\s*\)" -and $line -match "(context|_context)") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE003" `
                -Message "Using .Wait() blocks the thread. Use 'await' with async methods instead." `
                -Severity "Critical"
        }

        # Check for synchronous methods
        if ($line -match "\.(Find|First|FirstOrDefault|Single|SingleOrDefault|ToList|ToArray|Count|Any|All)\s*\(" -and 
            $line -notmatch "Async\s*\(" -and
            $line -match "(context|_context|DbSet)") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE004" `
                -Message "Consider using async method (e.g., FindAsync, FirstOrDefaultAsync) for database operations." `
                -Severity "High"
        }
    }
}

function Test-N1Patterns {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0
    $inLoop = $false
    $loopStartLine = 0

    foreach ($line in $content) {
        $lineNumber++

        # Detect loop start
        if ($line -match "\b(foreach|for|while)\s*\(") {
            $inLoop = $true
            $loopStartLine = $lineNumber
        }

        # Check for database calls inside loop
        if ($inLoop) {
            if ($line -match "(context|_context)\.\w+\.(Find|Where|First|Single|Include)" -or
                $line -match "await\s+.*\.(FindAsync|FirstAsync|SingleAsync|ToListAsync)") {
                Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE005" `
                    -Message "Database query inside loop - potential N+1 problem. Consider using Include() or batch query." `
                    -Severity "Critical"
            }
        }

        # Detect loop end (simplified)
        if ($inLoop -and $line -match "^\s*\}\s*$") {
            $inLoop = $false
        }
    }
}

function Test-MissingPagination {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for ToList without Skip/Take
        if ($line -match "\.ToList(Async)?\s*\(\s*\)" -and 
            $line -notmatch "\.(Skip|Take)\s*\(") {
            
            # Check surrounding lines for Skip/Take
            $startLine = [Math]::Max(0, $lineNumber - 5)
            $endLine = [Math]::Min($content.Count - 1, $lineNumber + 1)
            $surroundingLines = $content[$startLine..$endLine] -join "`n"
            
            if ($surroundingLines -notmatch "\.(Skip|Take)\s*\(" -and
                $surroundingLines -match "(context|_context)\.\w+") {
                Add-Issue -File $FilePath -Line $lineNumber -Rule "EFCORE006" `
                    -Message "Consider adding pagination (Skip/Take) for list queries to prevent loading large datasets." `
                    -Severity "Medium"
            }
        }
    }
}

function Invoke-Analysis {
    Write-Host "Starting EF Core analysis..." -ForegroundColor Cyan
    Write-Host "Path: $Path" -ForegroundColor Cyan

    if (-not (Test-Path $Path)) {
        Write-Host "Path not found: $Path" -ForegroundColor Red
        exit 1
    }

    $files = Get-DataFiles -BasePath $Path
    Write-Host "Found $($files.Count) files to analyze" -ForegroundColor Cyan

    foreach ($file in $files) {
        Test-ToListBeforeFilter -FilePath $file.FullName
        Test-MissingAsNoTracking -FilePath $file.FullName
        Test-SyncOverAsync -FilePath $file.FullName
        Test-N1Patterns -FilePath $file.FullName
        Test-MissingPagination -FilePath $file.FullName
    }

    Output-Results
}

function Output-Results {
    $criticalCount = ($script:Issues | Where-Object { $_.Severity -eq "Critical" }).Count
    $highCount = ($script:Issues | Where-Object { $_.Severity -eq "High" }).Count
    $mediumCount = ($script:Issues | Where-Object { $_.Severity -eq "Medium" }).Count
    $lowCount = ($script:Issues | Where-Object { $_.Severity -eq "Low" }).Count

    switch ($OutputFormat) {
        "json" {
            @{
                skill   = "efcore-best-practices"
                summary = @{
                    critical = $criticalCount
                    high     = $highCount
                    medium   = $mediumCount
                    low      = $lowCount
                    total    = $script:Issues.Count
                }
                issues  = $script:Issues
            } | ConvertTo-Json -Depth 10
        }
        "markdown" {
            Write-Output "# EF Core Analysis Report"
            Write-Output ""
            Write-Output "## Summary"
            Write-Output "| Severity | Count |"
            Write-Output "|----------|-------|"
            Write-Output "| Critical | $criticalCount |"
            Write-Output "| High | $highCount |"
            Write-Output "| Medium | $mediumCount |"
            Write-Output "| Low | $lowCount |"
            
            if ($script:Issues.Count -gt 0) {
                Write-Output ""
                Write-Output "## Issues"
                foreach ($issue in $script:Issues | Sort-Object Severity, File, Line) {
                    Write-Output "### $($issue.Rule)"
                    Write-Output "- **File**: ``$($issue.File)``"
                    Write-Output "- **Line**: $($issue.Line)"
                    Write-Output "- **Severity**: $($issue.Severity)"
                    Write-Output "- **Message**: $($issue.Message)"
                    Write-Output ""
                }
            }
        }
        default {
            Write-Host ""
            Write-Host "=== EF Core Analysis Complete ===" -ForegroundColor Cyan
            Write-Host "Critical: $criticalCount" -ForegroundColor $(if ($criticalCount -gt 0) { "Red" } else { "Green" })
            Write-Host "High: $highCount" -ForegroundColor $(if ($highCount -gt 0) { "Yellow" } else { "Green" })
            Write-Host "Medium: $mediumCount" -ForegroundColor "Cyan"
            Write-Host "Low: $lowCount" -ForegroundColor "Gray"
            Write-Host ""

            if ($script:Issues.Count -gt 0) {
                Write-Host "Issues found:" -ForegroundColor Yellow
                foreach ($issue in $script:Issues | Sort-Object Severity, File, Line) {
                    Write-Host "  [$($issue.Severity)] $($issue.Rule): $($issue.Message)" -ForegroundColor $(
                        switch ($issue.Severity) {
                            "Critical" { "Red" }
                            "High" { "Yellow" }
                            "Medium" { "Cyan" }
                            default { "Gray" }
                        }
                    )
                    Write-Host "    File: $($issue.File):$($issue.Line)" -ForegroundColor Gray
                    Write-Host ""
                }
            }
            else {
                Write-Host "No issues found! Your EF Core usage looks good." -ForegroundColor Green
            }
        }
    }

    if ($criticalCount -gt 0) {
        exit 1
    }
}

Invoke-Analysis
