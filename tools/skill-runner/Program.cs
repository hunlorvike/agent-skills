using System.CommandLine;
using System.Diagnostics;
using System.Text.Json;
using Spectre.Console;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace SkillRunner;

class Program
{
    static async Task<int> Main(string[] args)
    {
        var rootCommand = new RootCommand("ASP.NET Agent Skills Runner - Analyze projects against best practices");

        // List command
        var listCommand = new Command("list", "List available skills");
        var categoryOption = new Option<string?>("--category", "Filter by category");
        listCommand.AddOption(categoryOption);
        listCommand.SetHandler(ListSkills, categoryOption);

        // Check command
        var checkCommand = new Command("check", "Run skill analysis on a project");
        var skillArgument = new Argument<string>("skill", "Skill name to check");
        var pathOption = new Option<string>("--path", () => ".", "Path to the project");
        var outputOption = new Option<string>("--output", () => "console", "Output format (console, json, markdown)");
        checkCommand.AddArgument(skillArgument);
        checkCommand.AddOption(pathOption);
        checkCommand.AddOption(outputOption);
        checkCommand.SetHandler(CheckSkill, skillArgument, pathOption, outputOption);

        // Report command
        var reportCommand = new Command("report", "Generate a comprehensive report for all skills");
        var reportPathOption = new Option<string>("--path", () => ".", "Path to the project");
        var reportOutputOption = new Option<string>("--output", "Output file path");
        reportCommand.AddOption(reportPathOption);
        reportCommand.AddOption(reportOutputOption);
        reportCommand.SetHandler(GenerateReport, reportPathOption, reportOutputOption);

        // Info command
        var infoCommand = new Command("info", "Show details about a skill");
        var infoSkillArgument = new Argument<string>("skill", "Skill name");
        infoCommand.AddArgument(infoSkillArgument);
        infoCommand.SetHandler(ShowSkillInfo, infoSkillArgument);

        rootCommand.AddCommand(listCommand);
        rootCommand.AddCommand(checkCommand);
        rootCommand.AddCommand(reportCommand);
        rootCommand.AddCommand(infoCommand);

        return await rootCommand.InvokeAsync(args);
    }

    static void ListSkills(string? category)
    {
        var skillsPath = GetSkillsPath();
        
        if (!Directory.Exists(skillsPath))
        {
            AnsiConsole.MarkupLine("[red]Skills directory not found[/]");
            return;
        }

        var table = new Table();
        table.AddColumn("Category");
        table.AddColumn("Skill");
        table.AddColumn("Priority");
        table.AddColumn("Description");

        var categories = Directory.GetDirectories(skillsPath);
        
        foreach (var categoryPath in categories)
        {
            var categoryName = Path.GetFileName(categoryPath);
            
            if (!string.IsNullOrEmpty(category) && 
                !categoryName.Equals(category, StringComparison.OrdinalIgnoreCase))
                continue;

            var skillDirs = Directory.GetDirectories(categoryPath);
            
            foreach (var skillDir in skillDirs)
            {
                var skillFile = Path.Combine(skillDir, "SKILL.md");
                if (!File.Exists(skillFile))
                    continue;

                var metadata = ParseSkillMetadata(skillFile);
                if (metadata != null)
                {
                    var priorityColor = metadata.Priority?.ToLower() switch
                    {
                        "critical" => "red",
                        "high" => "yellow",
                        "medium" => "blue",
                        _ => "gray"
                    };

                    table.AddRow(
                        categoryName,
                        Path.GetFileName(skillDir),
                        $"[{priorityColor}]{metadata.Priority ?? "unknown"}[/]",
                        TruncateString(metadata.Description ?? "", 50)
                    );
                }
            }
        }

        AnsiConsole.Write(table);
    }

    static async Task CheckSkill(string skill, string path, string output)
    {
        var skillPath = FindSkillPath(skill);
        
        if (skillPath == null)
        {
            AnsiConsole.MarkupLine($"[red]Skill '{skill}' not found[/]");
            return;
        }

        var scriptPath = Path.Combine(skillPath, "scripts");
        
        if (!Directory.Exists(scriptPath))
        {
            AnsiConsole.MarkupLine($"[yellow]No scripts found for skill '{skill}'[/]");
            return;
        }

        var scripts = Directory.GetFiles(scriptPath, "*.ps1");
        
        if (scripts.Length == 0)
        {
            AnsiConsole.MarkupLine($"[yellow]No PowerShell scripts found for skill '{skill}'[/]");
            return;
        }

        AnsiConsole.MarkupLine($"[green]Running analysis for skill: {skill}[/]");
        AnsiConsole.MarkupLine($"[gray]Project path: {Path.GetFullPath(path)}[/]");

        foreach (var script in scripts)
        {
            await AnsiConsole.Status()
                .StartAsync($"Running {Path.GetFileName(script)}...", async ctx =>
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = "pwsh",
                        Arguments = $"-ExecutionPolicy Bypass -File \"{script}\" -Path \"{Path.GetFullPath(path)}\" -OutputFormat {output}",
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };

                    // Fallback to Windows PowerShell if pwsh not found
                    try
                    {
                        using var process = Process.Start(psi);
                        if (process == null)
                        {
                            psi.FileName = "powershell";
                            process?.Dispose();
                        }
                    }
                    catch
                    {
                        psi.FileName = "powershell";
                    }

                    using var proc = Process.Start(psi);
                    if (proc == null)
                    {
                        AnsiConsole.MarkupLine("[red]Failed to start PowerShell[/]");
                        return;
                    }

                    var outputText = await proc.StandardOutput.ReadToEndAsync();
                    var errorText = await proc.StandardError.ReadToEndAsync();

                    await proc.WaitForExitAsync();

                    if (!string.IsNullOrWhiteSpace(outputText))
                    {
                        Console.WriteLine(outputText);
                    }

                    if (!string.IsNullOrWhiteSpace(errorText))
                    {
                        AnsiConsole.MarkupLine($"[red]{errorText}[/]");
                    }
                });
        }
    }

    static async Task GenerateReport(string path, string? output)
    {
        var skillsPath = GetSkillsPath();
        var results = new List<SkillCheckResult>();

        await AnsiConsole.Progress()
            .StartAsync(async ctx =>
            {
                var task = ctx.AddTask("[green]Analyzing project[/]");
                
                var categories = Directory.GetDirectories(skillsPath);
                var totalSkills = categories.SelectMany(c => Directory.GetDirectories(c)).Count();
                var processedSkills = 0;

                foreach (var categoryPath in categories)
                {
                    var skillDirs = Directory.GetDirectories(categoryPath);
                    
                    foreach (var skillDir in skillDirs)
                    {
                        var skillName = Path.GetFileName(skillDir);
                        var scriptPath = Path.Combine(skillDir, "scripts");
                        
                        if (Directory.Exists(scriptPath))
                        {
                            var scripts = Directory.GetFiles(scriptPath, "*.ps1");
                            
                            foreach (var script in scripts)
                            {
                                var result = await RunScriptAsync(script, path);
                                if (result != null)
                                {
                                    results.Add(new SkillCheckResult
                                    {
                                        SkillName = skillName,
                                        Category = Path.GetFileName(categoryPath),
                                        Issues = result
                                    });
                                }
                            }
                        }

                        processedSkills++;
                        task.Value = (double)processedSkills / totalSkills * 100;
                    }
                }

                task.Value = 100;
            });

        // Generate report
        var report = new AnalysisReport
        {
            GeneratedAt = DateTime.UtcNow,
            ProjectPath = Path.GetFullPath(path),
            Results = results,
            Summary = new ReportSummary
            {
                TotalSkillsChecked = results.Count,
                TotalIssues = results.Sum(r => r.Issues?.Count ?? 0),
                CriticalIssues = results.Sum(r => r.Issues?.Count(i => i.Severity == "Critical") ?? 0),
                HighIssues = results.Sum(r => r.Issues?.Count(i => i.Severity == "High") ?? 0)
            }
        };

        var json = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });

        if (!string.IsNullOrEmpty(output))
        {
            await File.WriteAllTextAsync(output, json);
            AnsiConsole.MarkupLine($"[green]Report saved to {output}[/]");
        }
        else
        {
            Console.WriteLine(json);
        }

        // Summary table
        var summaryTable = new Table();
        summaryTable.AddColumn("Metric");
        summaryTable.AddColumn("Value");
        summaryTable.AddRow("Skills Checked", report.Summary.TotalSkillsChecked.ToString());
        summaryTable.AddRow("Total Issues", report.Summary.TotalIssues.ToString());
        summaryTable.AddRow("[red]Critical Issues[/]", report.Summary.CriticalIssues.ToString());
        summaryTable.AddRow("[yellow]High Issues[/]", report.Summary.HighIssues.ToString());

        AnsiConsole.Write(summaryTable);
    }

    static void ShowSkillInfo(string skill)
    {
        var skillPath = FindSkillPath(skill);
        
        if (skillPath == null)
        {
            AnsiConsole.MarkupLine($"[red]Skill '{skill}' not found[/]");
            return;
        }

        var skillFile = Path.Combine(skillPath, "SKILL.md");
        var metadata = ParseSkillMetadata(skillFile);

        if (metadata == null)
        {
            AnsiConsole.MarkupLine("[red]Could not parse skill metadata[/]");
            return;
        }

        var panel = new Panel(new Markup(
            $"[bold]{metadata.Name}[/]\n\n" +
            $"[gray]Description:[/] {metadata.Description}\n" +
            $"[gray]Version:[/] {metadata.Version}\n" +
            $"[gray]Priority:[/] {metadata.Priority}\n" +
            $"[gray]Categories:[/] {string.Join(", ", metadata.Categories ?? Array.Empty<string>())}\n\n" +
            $"[gray]Use when:[/]\n" +
            string.Join("\n", metadata.UseWhen?.Select(u => $"  • {u}") ?? Array.Empty<string>())
        ))
        {
            Header = new PanelHeader($"Skill: {skill}"),
            Border = BoxBorder.Rounded
        };

        AnsiConsole.Write(panel);

        // Check for scripts
        var scriptPath = Path.Combine(skillPath, "scripts");
        if (Directory.Exists(scriptPath))
        {
            var scripts = Directory.GetFiles(scriptPath);
            if (scripts.Any())
            {
                AnsiConsole.MarkupLine("\n[green]Available scripts:[/]");
                foreach (var script in scripts)
                {
                    AnsiConsole.MarkupLine($"  • {Path.GetFileName(script)}");
                }
            }
        }

        // Check for references
        var refPath = Path.Combine(skillPath, "references");
        if (Directory.Exists(refPath))
        {
            var refs = Directory.GetFiles(refPath, "*.md");
            if (refs.Any())
            {
                AnsiConsole.MarkupLine("\n[green]Reference documents:[/]");
                foreach (var r in refs)
                {
                    AnsiConsole.MarkupLine($"  • {Path.GetFileName(r)}");
                }
            }
        }
    }

    static string GetSkillsPath()
    {
        // Try to find skills relative to tool location
        var toolPath = AppContext.BaseDirectory;
        var paths = new[]
        {
            Path.Combine(toolPath, "..", "..", "..", "skills"),
            Path.Combine(toolPath, "..", "..", "skills"),
            Path.Combine(toolPath, "..", "skills"),
            Path.Combine(toolPath, "skills"),
            Path.Combine(Directory.GetCurrentDirectory(), "skills"),
            Path.Combine(Directory.GetCurrentDirectory(), "..", "skills")
        };

        foreach (var p in paths)
        {
            if (Directory.Exists(p))
                return Path.GetFullPath(p);
        }

        return Path.Combine(toolPath, "skills");
    }

    static string? FindSkillPath(string skill)
    {
        var skillsPath = GetSkillsPath();
        
        if (!Directory.Exists(skillsPath))
            return null;

        foreach (var category in Directory.GetDirectories(skillsPath))
        {
            var skillDir = Path.Combine(category, skill);
            if (Directory.Exists(skillDir))
                return skillDir;
        }

        return null;
    }

    static SkillMetadata? ParseSkillMetadata(string skillFile)
    {
        try
        {
            var content = File.ReadAllText(skillFile);
            
            // Extract YAML frontmatter
            if (!content.StartsWith("---"))
                return null;

            var endIndex = content.IndexOf("---", 3);
            if (endIndex < 0)
                return null;

            var yaml = content.Substring(3, endIndex - 3).Trim();

            var deserializer = new DeserializerBuilder()
                .WithNamingConvention(UnderscoredNamingConvention.Instance)
                .IgnoreUnmatchedProperties()
                .Build();

            return deserializer.Deserialize<SkillMetadata>(yaml);
        }
        catch
        {
            return null;
        }
    }

    static async Task<List<Issue>?> RunScriptAsync(string scriptPath, string projectPath)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\" -Path \"{Path.GetFullPath(projectPath)}\" -OutputFormat json",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            if (process == null)
                return null;

            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();

            if (string.IsNullOrWhiteSpace(output))
                return null;

            var result = JsonSerializer.Deserialize<ScriptOutput>(output, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            return result?.Issues;
        }
        catch
        {
            return null;
        }
    }

    static string TruncateString(string value, int maxLength)
    {
        if (string.IsNullOrEmpty(value))
            return value;
        return value.Length <= maxLength ? value : value[..(maxLength - 3)] + "...";
    }
}

class SkillMetadata
{
    public string? Name { get; set; }
    public string? Description { get; set; }
    public string? Version { get; set; }
    public string? Priority { get; set; }
    public string[]? Categories { get; set; }
    public string[]? UseWhen { get; set; }
    public string[]? Prerequisites { get; set; }
    public string[]? RelatedSkills { get; set; }
}

class ScriptOutput
{
    public string? Skill { get; set; }
    public Summary? Summary { get; set; }
    public List<Issue>? Issues { get; set; }
}

class Summary
{
    public int Critical { get; set; }
    public int High { get; set; }
    public int Medium { get; set; }
    public int Low { get; set; }
    public int Total { get; set; }
}

class Issue
{
    public string? File { get; set; }
    public int Line { get; set; }
    public string? Rule { get; set; }
    public string? Message { get; set; }
    public string? Severity { get; set; }
}

class SkillCheckResult
{
    public string SkillName { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public List<Issue>? Issues { get; set; }
}

class AnalysisReport
{
    public DateTime GeneratedAt { get; set; }
    public string ProjectPath { get; set; } = string.Empty;
    public List<SkillCheckResult> Results { get; set; } = new();
    public ReportSummary Summary { get; set; } = new();
}

class ReportSummary
{
    public int TotalSkillsChecked { get; set; }
    public int TotalIssues { get; set; }
    public int CriticalIssues { get; set; }
    public int HighIssues { get; set; }
}
