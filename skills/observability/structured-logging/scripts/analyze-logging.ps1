<#
.SYNOPSIS
    Analyzes logging practices in ASP.NET Core applications.

.DESCRIPTION
    Scans C# files for logging anti-patterns including:
    - String interpolation in log messages
    - Potential sensitive data logging
    - Missing structured properties
    - Inappropriate log levels

.PARAMETER Path
    The path to the project to analyze.

.PARAMETER OutputFormat
    Output format: 'console', 'json', or 'markdown'.

.EXAMPLE
    .\analyze-logging.ps1 -Path "C:\Projects\MyApi" -OutputFormat "console"
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

function Get-SourceFiles {
    param([string]$BasePath)

    Get-ChildItem -Path $BasePath -Filter "*.cs" -Recurse |
    Where-Object { $_.FullName -notmatch "\\(bin|obj|node_modules|Migrations)\\" }
}

function Test-StringInterpolationInLogs {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for string interpolation in log methods
        if ($line -match '_logger\.Log(Information|Warning|Error|Debug|Trace|Critical)\s*\(\s*\$"') {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG001" `
                -Message "Using string interpolation in log message. Use message template with named placeholders instead." `
                -Severity "High"
        }

        # Check for Log.X($"...") pattern with Serilog
        if ($line -match 'Log\.(Information|Warning|Error|Debug|Verbose|Fatal)\s*\(\s*\$"') {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG001" `
                -Message "Using string interpolation in Serilog message. Use message template with named placeholders instead." `
                -Severity "High"
        }

        # Check for string concatenation
        if ($line -match '_logger\.Log\w+\s*\([^)]*\+[^)]*\)') {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG002" `
                -Message "Using string concatenation in log message. Use message template with named placeholders instead." `
                -Severity "High"
        }
    }
}

function Test-SensitiveDataLogging {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    $sensitivePatterns = @(
        @{ Pattern = "password"; Term = "password" },
        @{ Pattern = "Password"; Term = "Password" },
        @{ Pattern = "secret"; Term = "secret" },
        @{ Pattern = "Secret"; Term = "Secret" },
        @{ Pattern = "token"; Term = "token" },
        @{ Pattern = "Token"; Term = "Token" },
        @{ Pattern = "apikey"; Term = "API key" },
        @{ Pattern = "ApiKey"; Term = "API key" },
        @{ Pattern = "creditcard"; Term = "credit card" },
        @{ Pattern = "CreditCard"; Term = "credit card" },
        @{ Pattern = "CardNumber"; Term = "card number" },
        @{ Pattern = "cvv"; Term = "CVV" },
        @{ Pattern = "ssn"; Term = "SSN" }
    )

    foreach ($line in $content) {
        $lineNumber++

        if ($line -match '_logger\.Log|Log\.(Information|Warning|Error|Debug)') {
            foreach ($sensitive in $sensitivePatterns) {
                if ($line -match "\{$($sensitive.Pattern)\}" -or 
                    $line -match "\{[^}]*$($sensitive.Pattern)[^}]*\}") {
                    Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG003" `
                        -Message "Potentially logging sensitive data ($($sensitive.Term)). Review and ensure proper masking." `
                        -Severity "Critical"
                }
            }
        }
    }
}

function Test-LogLevelUsage {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for LogError without exception
        if ($line -match '_logger\.LogError\s*\(\s*"' -and $line -notmatch 'exception|Exception|ex,|ex\)') {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG004" `
                -Message "LogError without exception parameter. Include the exception for proper stack trace logging." `
                -Severity "Medium"
        }

        # Check for LogInformation used for errors
        if ($line -match '_logger\.LogInformation.*\b(error|failed|exception|failure)\b' -and 
            $line -notmatch "no error|without error|error count") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG005" `
                -Message "Using LogInformation for error scenario. Consider using LogWarning or LogError instead." `
                -Severity "Medium"
        }
    }
}

function Test-MissingLogContext {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath -Raw

    # Check if file has logging but no correlation ID or request context
    if ($content -match '_logger\.Log' -or $content -match 'Log\.(Information|Warning)') {
        if ($content -notmatch 'CorrelationId|BeginScope|LogContext\.Push|RequestId') {
            # Only flag if this looks like a service or controller
            if ($content -match '(Service|Controller|Handler)\s*:\s*' -or 
                $content -match '\[ApiController\]' -or
                $content -match 'IRequestHandler') {
                
                $fileName = Split-Path $FilePath -Leaf
                Add-Issue -File $FilePath -Line 1 -Rule "LOG006" `
                    -Message "No correlation ID or request context found in logging. Consider adding for request tracing." `
                    -Severity "Low"
            }
        }
    }
}

function Test-LoggingPerformance {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0
    $inLoop = $false

    foreach ($line in $content) {
        $lineNumber++

        # Detect loop start
        if ($line -match '\b(foreach|for|while)\s*\(') {
            $inLoop = $true
        }

        # Check for logging inside loops
        if ($inLoop -and ($line -match '_logger\.Log' -or $line -match 'Log\.(Information|Debug)')) {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG007" `
                -Message "Logging inside loop can impact performance. Consider batch logging or moving outside loop." `
                -Severity "Medium"
        }

        # Simple loop end detection
        if ($inLoop -and $line -match '^\s*\}\s*$') {
            $inLoop = $false
        }

        # Check for expensive operations in log parameters without level check
        if ($line -match '_logger\.LogDebug\s*\([^)]*JsonSerializer\.Serialize' -or
            $line -match '_logger\.LogTrace\s*\([^)]*JsonSerializer\.Serialize') {
            
            # Check if there's an IsEnabled check nearby
            $startLine = [Math]::Max(0, $lineNumber - 3)
            $nearbyLines = $content[$startLine..($lineNumber - 1)] -join "`n"
            
            if ($nearbyLines -notmatch 'IsEnabled') {
                Add-Issue -File $FilePath -Line $lineNumber -Rule "LOG008" `
                    -Message "Expensive operation in Debug/Trace log without level check. Use _logger.IsEnabled() first." `
                    -Severity "Medium"
            }
        }
    }
}

function Invoke-Analysis {
    Write-Host "Starting logging analysis..." -ForegroundColor Cyan
    Write-Host "Path: $Path" -ForegroundColor Cyan

    if (-not (Test-Path $Path)) {
        Write-Host "Path not found: $Path" -ForegroundColor Red
        exit 1
    }

    $files = Get-SourceFiles -BasePath $Path
    Write-Host "Found $($files.Count) files to analyze" -ForegroundColor Cyan

    foreach ($file in $files) {
        Test-StringInterpolationInLogs -FilePath $file.FullName
        Test-SensitiveDataLogging -FilePath $file.FullName
        Test-LogLevelUsage -FilePath $file.FullName
        Test-MissingLogContext -FilePath $file.FullName
        Test-LoggingPerformance -FilePath $file.FullName
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
                skill   = "structured-logging"
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
            Write-Output "# Logging Analysis Report"
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
            Write-Host "=== Logging Analysis Complete ===" -ForegroundColor Cyan
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
                Write-Host "No issues found! Your logging practices look good." -ForegroundColor Green
            }
        }
    }

    if ($criticalCount -gt 0) {
        exit 1
    }
}

Invoke-Analysis
