---
name: configuration-management
description: Best practices for managing application configuration in ASP.NET Core including IConfiguration, Options pattern, secrets management, and environment-specific configurations.
version: 1.0.0
priority: medium
categories:
  - configuration
use_when:
  - "When managing application configuration"
  - "When using Azure Key Vault or secrets"
  - "When implementing Options pattern"
  - "When handling environment-specific configs"
  - "When validating configuration"
prerequisites:
  - "ASP.NET Core 8.0+"
related_skills:
  - dependency-injection-patterns
  - secure-headers
---

# Configuration Management Best Practices

## Overview

This skill covers comprehensive configuration management in ASP.NET Core. Proper configuration management ensures security, flexibility, and maintainability. This skill addresses:

- IConfiguration best practices
- Options pattern
- Configuration validation
- Secrets management
- Environment-specific configurations
- Configuration sources

## Rules

### Rule 1: Use Options Pattern for Configuration

**Priority**: High

**Description**: Use strongly-typed Options classes instead of directly accessing IConfiguration.

**Incorrect**:

```csharp
// Direct IConfiguration access
public class EmailService
{
    private readonly IConfiguration _configuration;

    public EmailService(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public async Task SendAsync(string to, string subject, string body)
    {
        var smtpHost = _configuration["Email:Smtp:Host"]; // Magic strings
        var smtpPort = _configuration.GetValue<int>("Email:Smtp:Port");
        // No validation, no IntelliSense, error-prone
    }
}
```

**Correct**:

```csharp
// Options class
public class EmailOptions
{
    public const string SectionName = "Email";

    [Required]
    public string Provider { get; set; } = string.Empty;

    [Required]
    [EmailAddress]
    public string From { get; set; } = string.Empty;

    public SmtpOptions Smtp { get; set; } = new();
    public SendGridOptions SendGrid { get; set; } = new();
}

public class SmtpOptions
{
    [Required]
    public string Host { get; set; } = string.Empty;

    [Range(1, 65535)]
    public int Port { get; set; } = 587;

    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

// Register and validate
builder.Services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection(EmailOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart(); // Fail fast if invalid

// Use in service
public class EmailService
{
    private readonly EmailOptions _options;
    private readonly ILogger<EmailService> _logger;

    public EmailService(
        IOptions<EmailOptions> options,
        ILogger<EmailService> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    public async Task SendAsync(string to, string subject, string body)
    {
        _logger.LogInformation("Sending email via {Provider} from {From}", 
            _options.Provider, _options.From);
        // Type-safe, validated configuration
    }
}
```

**Why**:
- Type-safe configuration
- IntelliSense support
- Configuration validation
- Better maintainability
- Compile-time checking

---

### Rule 2: Manage Secrets Securely

**Priority**: Critical

**Description**: Never commit secrets to source control. Use User Secrets, Azure Key Vault, or environment variables.

**Incorrect**:

```csharp
// Secrets in appsettings.json - committed to git
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=prod;Database=MyDb;Password=secret123"
  },
  "ApiKeys": {
    "SendGrid": "SG.secret-key-here"
  }
}

// Hardcoded secrets
var apiKey = "SG.secret-key-here"; // Never do this!
```

**Correct**:

```csharp
// Development: User Secrets
// Run: dotnet user-secrets init
// Run: dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Server=..."
builder.Configuration.AddUserSecrets<Program>();

// Production: Environment variables
// Set: ConnectionStrings__DefaultConnection=Server=...
builder.Configuration.AddEnvironmentVariables();

// Or Azure Key Vault
builder.Configuration.AddAzureKeyVault(
    new Uri($"https://{builder.Configuration["KeyVault:VaultName"]}.vault.azure.net/"),
    new DefaultAzureCredential());

// appsettings.json - no secrets
{
  "ConnectionStrings": {
    "DefaultConnection": "" // Empty, loaded from secrets
  },
  "Email": {
    "Provider": "SendGrid"
  }
}

// Access securely
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
// Or via Options
builder.Services.Configure<ConnectionStringsOptions>(
    builder.Configuration.GetSection("ConnectionStrings"));
```

**Why**:
- Prevents secret exposure
- Security best practice
- Compliance requirements
- Separate config from code
- Environment-specific secrets

---

### Rule 3: Validate Configuration on Startup

**Priority**: High

**Description**: Validate configuration at startup to fail fast if configuration is invalid.

**Incorrect**:

```csharp
// No validation - fails at runtime
builder.Services.Configure<EmailOptions>(
    builder.Configuration.GetSection("Email"));

// App starts, but fails when EmailService is used
public class EmailService
{
    public EmailService(IOptions<EmailOptions> options)
    {
        // Options.From might be null - fails later
        var from = options.Value.From; // NullReferenceException at runtime
    }
}
```

**Correct**:

```csharp
// Validate with Data Annotations
public class EmailOptions
{
    [Required(ErrorMessage = "Email From address is required")]
    [EmailAddress(ErrorMessage = "Invalid email format")]
    public string From { get; set; } = string.Empty;

    [Required]
    [Range(1, 65535, ErrorMessage = "Port must be between 1 and 65535")]
    public int Port { get; set; }
}

builder.Services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection("Email"))
    .ValidateDataAnnotations()
    .ValidateOnStart(); // Fails at startup if invalid

// Or use FluentValidation
public class EmailOptionsValidator : AbstractValidator<EmailOptions>
{
    public EmailOptionsValidator()
    {
        RuleFor(x => x.From)
            .NotEmpty().WithMessage("Email From is required")
            .EmailAddress().WithMessage("Invalid email format");

        RuleFor(x => x.Port)
            .InclusiveBetween(1, 65535)
            .WithMessage("Port must be between 1 and 65535");

        RuleFor(x => x)
            .Must(x => x.Provider switch
            {
                "Smtp" => !string.IsNullOrEmpty(x.Smtp.Host),
                "SendGrid" => !string.IsNullOrEmpty(x.SendGrid.ApiKey),
                _ => false
            })
            .WithMessage("Provider-specific configuration is invalid");
    }
}

builder.Services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection("Email"))
    .ValidateFluentValidation()
    .ValidateOnStart();
```

**Why**:
- Fail fast on startup
- Prevents runtime errors
- Clear error messages
- Better developer experience
- Production safety

---

### Rule 4: Use Environment-Specific Configuration

**Priority**: High

**Description**: Use different configuration sources for different environments.

**Incorrect**:

```csharp
// Same configuration for all environments
var builder = WebApplication.CreateBuilder(args);
// Only appsettings.json loaded

// Hardcoded environment checks
if (Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") == "Production")
{
    // Configuration logic mixed with code
}
```

**Correct**:

```csharp
// Environment-specific configuration
var builder = WebApplication.CreateBuilder(args);

// Load base configuration
builder.Configuration.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);

// Load environment-specific configuration (overrides base)
var environment = builder.Environment.EnvironmentName;
builder.Configuration.AddJsonFile(
    $"appsettings.{environment}.json",
    optional: true,
    reloadOnChange: true);

// Development: User Secrets
if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddUserSecrets<Program>();
}

// Production: Azure Key Vault
if (builder.Environment.IsProduction())
{
    builder.Configuration.AddAzureKeyVault(
        new Uri($"https://{builder.Configuration["KeyVault:VaultName"]}.vault.azure.net/"),
        new DefaultAzureCredential());
}

// Environment variables (highest priority, overrides all)
builder.Configuration.AddEnvironmentVariables();

// Configuration hierarchy (last wins):
// 1. appsettings.json
// 2. appsettings.{Environment}.json
// 3. User Secrets (Development)
// 4. Azure Key Vault (Production)
// 5. Environment variables

// appsettings.Development.json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug"
    }
  },
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Database=MyApp_Dev"
  }
}

// appsettings.Production.json
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning"
    }
  }
  // ConnectionStrings loaded from Key Vault
}
```

**Why**:
- Environment-specific settings
- Secure production configs
- Easy environment switching
- Configuration hierarchy
- Best practice

---

### Rule 5: Use IConfiguration Correctly

**Priority**: Medium

**Description**: Access configuration values correctly with proper defaults and type conversion.

**Incorrect**:

```csharp
// No null checks
var apiKey = builder.Configuration["ApiKeys:SendGrid"]; // Can be null

// No type conversion
var port = builder.Configuration["Smtp:Port"]; // Returns string, not int

// No defaults
var timeout = builder.Configuration["HttpClient:Timeout"]; // Null if not set
```

**Correct**:

```csharp
// With defaults
var apiKey = builder.Configuration["ApiKeys:SendGrid"] 
    ?? throw new InvalidOperationException("SendGrid API key not configured");

// Type conversion with defaults
var port = builder.Configuration.GetValue<int>("Smtp:Port", 587); // Default 587
var timeout = builder.Configuration.GetValue<TimeSpan>("HttpClient:Timeout", TimeSpan.FromSeconds(30));

// Using GetSection
var emailSection = builder.Configuration.GetSection("Email");
var provider = emailSection["Provider"] ?? "Smtp";
var from = emailSection["From"] ?? "noreply@example.com";

// Or use Options pattern (recommended)
builder.Services.Configure<EmailOptions>(options =>
{
    options.Provider = builder.Configuration["Email:Provider"] ?? "Smtp";
    options.From = builder.Configuration["Email:From"] 
        ?? throw new InvalidOperationException("Email:From is required");
});

// Validate required values
var requiredSettings = new[]
{
    "ConnectionStrings:DefaultConnection",
    "Email:From",
    "ApiKeys:SendGrid"
};

foreach (var setting in requiredSettings)
{
    if (string.IsNullOrEmpty(builder.Configuration[setting]))
    {
        throw new InvalidOperationException($"Required configuration '{setting}' is missing");
    }
}
```

**Why**:
- Prevents null reference exceptions
- Type-safe access
- Clear defaults
- Better error messages
- Production safety

---

### Rule 6: Reload Configuration at Runtime

**Priority**: Medium

**Description**: Use IOptionsSnapshot or IOptionsMonitor for reloadable configuration.

**Incorrect**:

```csharp
// IOptions - never reloads
public class EmailService
{
    private readonly EmailOptions _options;

    public EmailService(IOptions<EmailOptions> options)
    {
        _options = options.Value; // Captured at construction, never updates
    }
}
```

**Correct**:

```csharp
// IOptionsSnapshot - reloads per request scope
public class EmailService
{
    private readonly IOptionsSnapshot<EmailOptions> _options;

    public EmailService(IOptionsSnapshot<EmailOptions> options)
    {
        _options = options;
    }

    public async Task SendAsync(string to, string subject, string body)
    {
        var currentOptions = _options.Value; // Gets latest value per request
        // Use currentOptions
    }
}

// IOptionsMonitor - reloads and notifies
public class EmailService
{
    private readonly IOptionsMonitor<EmailOptions> _optionsMonitor;

    public EmailService(IOptionsMonitor<EmailOptions> optionsMonitor)
    {
        _optionsMonitor = optionsMonitor;
        
        // Listen for changes
        _optionsMonitor.OnChange(options =>
        {
            _logger.LogInformation("Email configuration reloaded. Provider: {Provider}", 
                options.Provider);
        });
    }

    public async Task SendAsync(string to, string subject, string body)
    {
        var currentOptions = _optionsMonitor.CurrentValue; // Always latest
        // Use currentOptions
    }
}

// Configure reload on change
builder.Services.Configure<EmailOptions>(
    builder.Configuration.GetSection("Email"),
    reloadOnChange: true); // Reloads when appsettings.json changes
```

**Why**:
- Dynamic configuration updates
- No app restart needed
- Better flexibility
- Production hot-reload
- Modern configuration management

---

## Integration Example

Complete configuration setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// Configuration sources
builder.Configuration
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true)
    .AddEnvironmentVariables();

if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddUserSecrets<Program>();
}

if (builder.Environment.IsProduction())
{
    builder.Configuration.AddAzureKeyVault(
        new Uri($"https://{builder.Configuration["KeyVault:VaultName"]}.vault.azure.net/"),
        new DefaultAzureCredential());
}

// Options with validation
builder.Services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection(EmailOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();

// Services using options
builder.Services.AddScoped<IEmailService, EmailService>();

var app = builder.Build();
app.Run();
```

## Checklist

- [ ] Options pattern used for configuration
- [ ] Secrets managed securely (User Secrets, Key Vault)
- [ ] Configuration validated on startup
- [ ] Environment-specific configs configured
- [ ] IConfiguration used correctly with defaults
- [ ] Reloadable configuration when needed
- [ ] No secrets in source control
- [ ] Configuration hierarchy understood

## References

- [Configuration in ASP.NET Core](https://docs.microsoft.com/aspnet/core/fundamentals/configuration/)
- [Options Pattern](https://docs.microsoft.com/aspnet/core/fundamentals/configuration/options)
- [User Secrets](https://docs.microsoft.com/aspnet/core/security/app-secrets)
- [Azure Key Vault](https://docs.microsoft.com/azure/key-vault/general/overview)

## Changelog

### v1.0.0
- Initial release
- 6 core rules for configuration management
