---
name: health-checks
description: Best practices for implementing health checks in ASP.NET Core including liveness, readiness probes, and dependency health checks for Kubernetes and monitoring systems.
version: 1.0.0
priority: high
categories:
  - observability
  - monitoring
  - kubernetes
use_when:
  - "When deploying to Kubernetes"
  - "When setting up monitoring"
  - "When implementing graceful shutdown"
  - "When checking system dependencies"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.Extensions.Diagnostics.HealthChecks"
related_skills:
  - structured-logging
  - distributed-tracing
---

# Health Checks Best Practices

## Overview

This skill covers implementing health checks in ASP.NET Core for monitoring application and dependency health, essential for Kubernetes deployments and monitoring systems.

## Rules

### Rule 1: Implement Liveness and Readiness Probes

**Priority**: High

**Description**: Use liveness to detect deadlocks and readiness to check if app can accept traffic.

**Incorrect**:

```csharp
// No health checks
var app = builder.Build();
app.MapControllers();
app.Run();
```

**Correct**:

```csharp
// Health checks configuration
builder.Services.AddHealthChecks()
    // Liveness - is the app running?
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: new[] { "liveness" })
    
    // Readiness - can the app accept traffic?
    .AddDbContextCheck<AppDbContext>(tags: new[] { "readiness" })
    .AddCheck<DatabaseHealthCheck>("database", tags: new[] { "readiness" })
    .AddCheck<ExternalApiHealthCheck>("external-api", tags: new[] { "readiness" });

var app = builder.Build();

// Liveness probe - quick check if app is alive
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("liveness"),
    AllowCachingResponses = false
});

// Readiness probe - check if app is ready to serve
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("readiness"),
    AllowCachingResponses = false
});

// Combined health check
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});
```

**Why**:
- Kubernetes uses liveness to restart containers
- Readiness prevents traffic to unhealthy pods
- Better orchestration behavior
- Essential for zero-downtime deployments

---

### Rule 2: Check Critical Dependencies

**Priority**: High

**Description**: Monitor health of databases, external APIs, and other critical dependencies.

**Correct**:

```csharp
// Custom health check for database
public class DatabaseHealthCheck : IHealthCheck
{
    private readonly AppDbContext _context;

    public DatabaseHealthCheck(AppDbContext context)
    {
        _context = context;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            // Quick query to verify database connectivity
            var canConnect = await _context.Database.CanConnectAsync(cancellationToken);
            
            if (!canConnect)
                return HealthCheckResult.Unhealthy("Database is not accessible");

            // Optional: Check if database is read-only
            var isReadOnly = await _context.Database.ExecuteSqlRawAsync(
                "SELECT @@readonly", cancellationToken) == 1;

            if (isReadOnly)
                return HealthCheckResult.Degraded("Database is in read-only mode");

            return HealthCheckResult.Healthy("Database is accessible");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Database check failed", ex);
        }
    }
}

// Health check for external API
public class ExternalApiHealthCheck : IHealthCheck
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<ExternalApiHealthCheck> _logger;

    public ExternalApiHealthCheck(HttpClient httpClient, ILogger<ExternalApiHealthCheck> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var response = await _httpClient.GetAsync("/health", cancellationToken);
            
            if (response.IsSuccessStatusCode)
                return HealthCheckResult.Healthy("External API is responding");

            return HealthCheckResult.Degraded($"External API returned {response.StatusCode}");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "External API health check failed");
            return HealthCheckResult.Unhealthy("External API is not accessible", ex);
        }
    }
}

// Register health checks
builder.Services.AddHealthChecks()
    .AddCheck<DatabaseHealthCheck>("database")
    .AddCheck<ExternalApiHealthCheck>("external-api")
    .AddRedis(connectionString, tags: new[] { "redis" })
    .AddRabbitMQ(connectionString, tags: new[] { "rabbitmq" });
```

**Why**:
- Detects dependency failures early
- Prevents cascading failures
- Better system observability
- Enables automatic recovery

---

### Rule 3: Configure Health Check UI

**Priority**: Medium

**Description**: Provide human-readable health check UI for debugging.

**Correct**:

```csharp
// Install: AspNetCore.HealthChecks.UI

builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>()
    .AddCheck<DatabaseHealthCheck>("database");

builder.Services.AddHealthChecksUI(options =>
{
    options.SetEvaluationTimeInSeconds(10);
    options.MaximumHistoryEntriesPerEndpoint(50);
    options.AddHealthCheckEndpoint("API", "/health");
})
.AddInMemoryStorage();

var app = builder.Build();

app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});

app.MapHealthChecksUI(options =>
{
    options.UIPath = "/health-ui";
    options.ApiPath = "/health-api";
});
```

**Why**:
- Visual health status
- Historical health data
- Easier debugging
- Better monitoring dashboard

---

## Integration Example

Complete health checks setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));

// Health checks
builder.Services.AddHealthChecks()
    .AddCheck("self", () => HealthCheckResult.Healthy(), tags: new[] { "liveness" })
    .AddDbContextCheck<AppDbContext>(tags: new[] { "readiness" })
    .AddCheck<DatabaseHealthCheck>("database", tags: new[] { "readiness" })
    .AddCheck<ExternalApiHealthCheck>("external-api", tags: new[] { "readiness" })
    .AddRedis(redisConnectionString, tags: new[] { "readiness" });

var app = builder.Build();

// Health endpoints
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("liveness")
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("readiness")
});

app.MapHealthChecks("/health");

app.Run();
```

## Checklist

- [ ] Liveness probe implemented
- [ ] Readiness probe implemented
- [ ] Database health check
- [ ] External dependencies checked
- [ ] Health check UI configured (optional)
- [ ] Kubernetes probes configured
- [ ] Health check endpoints secured

## References

- [Health Checks](https://docs.microsoft.com/aspnet/core/host-and-deploy/health-checks)
- [Kubernetes Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## Changelog

### v1.0.0
- Initial release
- 3 core rules for health checks
