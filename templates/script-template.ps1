<#
.SYNOPSIS
    Template script for skill automation.

.DESCRIPTION
    This script analyzes ASP.NET code for [skill-name] compliance.
    Replace this description with the actual skill purpose.

.PARAMETER Path
    The path to the project or solution to analyze.

.PARAMETER OutputFormat
    The output format: 'console', 'json', or 'markdown'.

.EXAMPLE
    .\analyze-skill.ps1 -Path "C:\Projects\MyApi" -OutputFormat "console"

.NOTES
    Author: ASP.NET Agent Skills
    Version: 1.0.0
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet("console", "json", "markdown")]
    [string]$OutputFormat = "console"
)

# Script configuration
$ErrorActionPreference = "Stop"
$script:Issues = @()
$script:Warnings = @()
$script:Info = @()

#region Helper Functions

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

function Get-CSharpFiles {
    param([string]$BasePath)

    Get-ChildItem -Path $BasePath -Filter "*.cs" -Recurse |
    Where-Object { $_.FullName -notmatch "\\(bin|obj|node_modules)\\" }
}

#endregion

#region Analysis Functions

function Test-Rule1 {
    <#
    .SYNOPSIS
        Checks for Rule 1 compliance.
    #>
    param([string]$FilePath)

    $content = Get-Content -Path $FilePath -Raw

    # Example: Check for something specific
    # Modify this logic based on the actual rule
    if ($content -match "BadPattern") {
        Add-Issue -File $FilePath -Line 1 -Rule "RULE001" `
            -Message "Found bad pattern that should be avoided" `
            -Severity "High"
    }
}

function Test-Rule2 {
    <#
    .SYNOPSIS
        Checks for Rule 2 compliance.
    #>
    param([string]$FilePath)

    # Add rule-specific logic here
}

#endregion

#region Main Execution

function Invoke-SkillAnalysis {
    Write-SkillOutput "Starting skill analysis..." -Level "Info"
    Write-SkillOutput "Path: $Path" -Level "Info"

    if (-not (Test-Path $Path)) {
        Write-SkillOutput "Path not found: $Path" -Level "Error"
        exit 1
    }

    $files = Get-CSharpFiles -BasePath $Path
    $totalFiles = $files.Count

    Write-SkillOutput "Found $totalFiles C# files to analyze" -Level "Info"

    foreach ($file in $files) {
        # Run all rule checks
        Test-Rule1 -FilePath $file.FullName
        Test-Rule2 -FilePath $file.FullName
    }

    # Output results
    Output-Results
}

function Output-Results {
    $criticalCount = ($script:Issues | Where-Object { $_.Severity -eq "Critical" }).Count
    $highCount = ($script:Issues | Where-Object { $_.Severity -eq "High" }).Count
    $mediumCount = ($script:Issues | Where-Object { $_.Severity -eq "Medium" }).Count
    $lowCount = ($script:Issues | Where-Object { $_.Severity -eq "Low" }).Count

    switch ($OutputFormat) {
        "json" {
            $result = @{
                summary = @{
                    critical = $criticalCount
                    high     = $highCount
                    medium   = $mediumCount
                    low      = $lowCount
                    total    = $script:Issues.Count
                }
                issues  = $script:Issues
            }
            $result | ConvertTo-Json -Depth 10
        }
        "markdown" {
            Write-Output "# Skill Analysis Report"
            Write-Output ""
            Write-Output "## Summary"
            Write-Output "| Severity | Count |"
            Write-Output "|----------|-------|"
            Write-Output "| Critical | $criticalCount |"
            Write-Output "| High | $highCount |"
            Write-Output "| Medium | $mediumCount |"
            Write-Output "| Low | $lowCount |"
            Write-Output ""
            Write-Output "## Issues"
            foreach ($issue in $script:Issues) {
                Write-Output "### $($issue.Rule): $($issue.Message)"
                Write-Output "- **File**: $($issue.File)"
                Write-Output "- **Line**: $($issue.Line)"
                Write-Output "- **Severity**: $($issue.Severity)"
                Write-Output ""
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
                foreach ($issue in $script:Issues) {
                    Write-Output "  [$($issue.Severity)] $($issue.Rule): $($issue.Message)"
                    Write-Output "    File: $($issue.File):$($issue.Line)"
                }
            }
            else {
                Write-SkillOutput "No issues found!" -Level "Success"
            }
        }
    }

    # Exit with error code if critical issues found
    if ($criticalCount -gt 0) {
        exit 1
    }
}

#endregion

# Run the analysis
Invoke-SkillAnalysis
