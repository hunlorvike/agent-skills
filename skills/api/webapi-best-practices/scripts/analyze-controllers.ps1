<#
.SYNOPSIS
    Analyzes ASP.NET Web API controllers for best practices compliance.

.DESCRIPTION
    This script scans ASP.NET Core controllers and checks for:
    - Proper HTTP status code usage
    - Use of ActionResult<T> instead of IActionResult
    - ProducesResponseType attributes
    - Async/await patterns
    - Route conventions

.PARAMETER Path
    The path to the project or solution to analyze.

.PARAMETER OutputFormat
    The output format: 'console', 'json', or 'markdown'.

.EXAMPLE
    .\analyze-controllers.ps1 -Path "C:\Projects\MyApi" -OutputFormat "console"
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

function Write-SkillOutput {
    param(
        [string]$Message,
        [ValidateSet("Error", "Warning", "Info", "Success")]
        [string]$Level = "Info"
    )

    $color = switch ($Level) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Info" { "Cyan" }
        "Success" { "Green" }
    }

    if ($OutputFormat -eq "console") {
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

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

function Get-ControllerFiles {
    param([string]$BasePath)

    Get-ChildItem -Path $BasePath -Filter "*Controller*.cs" -Recurse |
    Where-Object { $_.FullName -notmatch "\\(bin|obj|node_modules|Tests?)\\" }
}

function Test-ActionResultUsage {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for IActionResult without generic type
        if ($line -match "public\s+(async\s+)?Task<IActionResult>" -or 
            $line -match "public\s+IActionResult\s+") {
            
            # Skip if it's a proper use case (DELETE, some PUT scenarios)
            if ($line -notmatch "(Delete|Remove|Void)") {
                Add-Issue -File $FilePath -Line $lineNumber -Rule "WEBAPI001" `
                    -Message "Consider using ActionResult<T> instead of IActionResult for type safety" `
                    -Severity "Medium"
            }
        }
    }
}

function Test-StatusCodeUsage {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath -Raw
    $lines = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $lines) {
        $lineNumber++

        # Check for Ok() returning null potentially
        if ($line -match "return\s+Ok\s*\(\s*\w+\s*\)" -and 
            $content -notmatch "if\s*\(\s*\w+\s*(==|is)\s*null") {
            
            # This is a simplified check - might have false positives
            if ($line -match "return\s+Ok\s*\(\s*(\w+)\s*\)") {
                $varName = $matches[1]
                # Check if there's no null check before this return
                $methodStart = $lineNumber - 20
                if ($methodStart -lt 0) { $methodStart = 0 }
                $methodContent = $lines[$methodStart..$lineNumber] -join "`n"
                
                if ($methodContent -notmatch "if\s*\(\s*$varName\s*(==|is)\s*null") {
                    Add-Issue -File $FilePath -Line $lineNumber -Rule "WEBAPI002" `
                        -Message "Returning Ok() without null check - consider returning NotFound() when resource is null" `
                        -Severity "High"
                }
            }
        }

        # Check for POST not returning CreatedAtAction
        if ($line -match "\[HttpPost\]" -or $line -match "\[HttpPost\s*\(") {
            # Look ahead for return statement
            for ($i = $lineNumber; $i -lt [Math]::Min($lineNumber + 30, $lines.Count); $i++) {
                if ($lines[$i] -match "return\s+Ok\s*\(") {
                    Add-Issue -File $FilePath -Line ($i + 1) -Rule "WEBAPI003" `
                        -Message "POST action should return CreatedAtAction() with 201 status, not Ok()" `
                        -Severity "High"
                    break
                }
                if ($lines[$i] -match "return\s+Created") {
                    break
                }
                if ($lines[$i] -match "^\s*\}\s*$" -and $lines[$i - 1] -notmatch "^\s*\{") {
                    break
                }
            }
        }
    }
}

function Test-ProducesResponseType {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0
    $inMethod = $false
    $hasProducesAttribute = $false
    $methodStartLine = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for HTTP method attributes
        if ($line -match "\[(Http(Get|Post|Put|Patch|Delete))") {
            $inMethod = $true
            $hasProducesAttribute = $false
            $methodStartLine = $lineNumber
        }

        if ($inMethod -and $line -match "\[ProducesResponseType") {
            $hasProducesAttribute = $true
        }

        # Check when we hit the method signature
        if ($inMethod -and $line -match "public\s+(async\s+)?") {
            if (-not $hasProducesAttribute) {
                Add-Issue -File $FilePath -Line $methodStartLine -Rule "WEBAPI004" `
                    -Message "Missing [ProducesResponseType] attribute - add for OpenAPI documentation" `
                    -Severity "Medium"
            }
            $inMethod = $false
        }
    }
}

function Test-AsyncAwaitPattern {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for .Result or .Wait() usage
        if ($line -match "\.Result\b" -or $line -match "\.Wait\s*\(\s*\)") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "WEBAPI005" `
                -Message "Avoid .Result or .Wait() - use async/await instead to prevent deadlocks" `
                -Severity "Critical"
        }

        # Check for synchronous database calls
        if ($line -match "\.(Find|First|Single|ToList|Any|Count)\s*\(" -and 
            $line -notmatch "Async\s*\(") {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "WEBAPI006" `
                -Message "Consider using async version (e.g., FindAsync, FirstOrDefaultAsync) for database operations" `
                -Severity "High"
        }
    }
}

function Test-RouteConventions {
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath
    $lineNumber = 0

    foreach ($line in $content) {
        $lineNumber++

        # Check for verbs in route
        if ($line -match '\[Route\s*\(\s*"[^"]*\b(get|post|put|delete|create|update|remove)\b[^"]*"\s*\)') {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "WEBAPI007" `
                -Message "Avoid verbs in routes - use HTTP methods to convey action instead" `
                -Severity "Medium"
        }

        # Check for missing route constraint on id
        if ($line -match '\{id\}' -and $line -notmatch '\{id:int\}' -and $line -notmatch '\{id:guid\}') {
            Add-Issue -File $FilePath -Line $lineNumber -Rule "WEBAPI008" `
                -Message "Consider adding route constraint (e.g., {id:int}) for type safety" `
                -Severity "Low"
        }
    }
}

function Invoke-Analysis {
    Write-SkillOutput "Starting Web API best practices analysis..." -Level "Info"
    Write-SkillOutput "Path: $Path" -Level "Info"

    if (-not (Test-Path $Path)) {
        Write-SkillOutput "Path not found: $Path" -Level "Error"
        exit 1
    }

    $files = Get-ControllerFiles -BasePath $Path
    $totalFiles = $files.Count

    Write-SkillOutput "Found $totalFiles controller files to analyze" -Level "Info"

    foreach ($file in $files) {
        Write-SkillOutput "Analyzing: $($file.Name)" -Level "Info"
        
        Test-ActionResultUsage -FilePath $file.FullName
        Test-StatusCodeUsage -FilePath $file.FullName
        Test-ProducesResponseType -FilePath $file.FullName
        Test-AsyncAwaitPattern -FilePath $file.FullName
        Test-RouteConventions -FilePath $file.FullName
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
                skill   = "webapi-best-practices"
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
            Write-Output "# Web API Best Practices Analysis Report"
            Write-Output ""
            Write-Output "## Summary"
            Write-Output "| Severity | Count |"
            Write-Output "|----------|-------|"
            Write-Output "| Critical | $criticalCount |"
            Write-Output "| High | $highCount |"
            Write-Output "| Medium | $mediumCount |"
            Write-Output "| Low | $lowCount |"
            Write-Output ""
            
            if ($script:Issues.Count -gt 0) {
                Write-Output "## Issues"
                foreach ($issue in $script:Issues | Sort-Object Severity) {
                    Write-Output "### $($issue.Rule): $($issue.Message)"
                    Write-Output "- **File**: ``$($issue.File)``"
                    Write-Output "- **Line**: $($issue.Line)"
                    Write-Output "- **Severity**: $($issue.Severity)"
                    Write-Output ""
                }
            }
        }
        default {
            Write-Output ""
            Write-SkillOutput "=== Analysis Complete ===" -Level "Info"
            Write-SkillOutput "Critical: $criticalCount" -Level $(if ($criticalCount -gt 0) { "Error" } else { "Success" })
            Write-SkillOutput "High: $highCount" -Level $(if ($highCount -gt 0) { "Warning" } else { "Success" })
            Write-SkillOutput "Medium: $mediumCount" -Level "Info"
            Write-SkillOutput "Low: $lowCount" -Level "Info"
            Write-Output ""

            if ($script:Issues.Count -gt 0) {
                Write-SkillOutput "Issues found:" -Level "Warning"
                foreach ($issue in $script:Issues | Sort-Object Severity, File, Line) {
                    Write-Output "  [$($issue.Severity)] $($issue.Rule): $($issue.Message)"
                    Write-Output "    File: $($issue.File):$($issue.Line)"
                    Write-Output ""
                }
            }
            else {
                Write-SkillOutput "No issues found! Your API follows best practices." -Level "Success"
            }
        }
    }

    if ($criticalCount -gt 0) {
        exit 1
    }
}

Invoke-Analysis
