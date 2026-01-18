---
name: structured-logging
description: Best practices for implementing structured logging in ASP.NET Core applications using Serilog, NLog, or built-in logging with proper correlation IDs, log levels, and formatting.
version: 1.0.0
priority: critical
categories:
  - observability
  - logging
  - diagnostics
use_when:
  - "When setting up logging for a new application"
  - "When reviewing logging implementation"
  - "When debugging production issues"
  - "When implementing distributed tracing"
  - "When configuring log aggregation"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Serilog or Microsoft.Extensions.Logging"
related_skills:
  - distributed-tracing
  - health-checks
  - webapi-best-practices
---

# Structured Logging Best Practices

## Overview

Structured logging captures log data in a consistent, queryable format instead of plain text. This skill covers:

- Proper log level usage
- Structured message templates
- Correlation IDs for request tracing
- Performance-conscious logging
- Integration with log aggregation tools

## Rules

### Rule 1: Use Message Templates with Structured Properties

**Priority**: Critical

**Description**: Use message templates with named placeholders instead of string interpolation. This enables proper indexing and querying in log aggregation systems.

**Incorrect**:

```csharp
// String interpolation - loses structure
_logger.LogInformation($"Processing order {orderId} for customer {customerId}");

// Concatenation - also loses structure
_logger.LogInformation("Processing order " + orderId + " for customer " + customerId);

// ToString() - loses type information
_logger.LogInformation("Order total: " + order.Total.ToString());

// Anonymous objects without templates
_logger.LogInformation("Order processed", new { OrderId = orderId, Total = total });
```

**Correct**:

```csharp
// Named placeholders - structured and queryable
_logger.LogInformation(
    "Processing order {OrderId} for customer {CustomerId}",
    orderId,
    customerId);

// Complex objects with destructuring
_logger.LogInformation(
    "Order {OrderId} created with {ItemCount} items. Details: {@Order}",
    order.Id,
    order.Items.Count,
    order);

// Consistent property naming (PascalCase)
_logger.LogInformation(
    "User {UserId} logged in from {IpAddress} at {LoginTime}",
    userId,
    ipAddress,
    DateTime.UtcNow);

// With Serilog - explicit destructuring
Log.Information(
    "Processing payment {@PaymentDetails} for order {OrderId}",
    new { Amount = payment.Amount, Currency = payment.Currency },
    orderId);
```

**Why**:
- Structured properties are searchable in tools like Seq, Elastic, Application Insights
- Type information is preserved (int, datetime, etc.)
- Avoids unnecessary string allocations
- Enables powerful log queries like "find all logs where OrderId = 12345"

---

### Rule 2: Use Appropriate Log Levels

**Priority**: Critical

**Description**: Use the correct log level for each message to enable proper filtering and alerting.

**Incorrect**:

```csharp
// Everything as Information
_logger.LogInformation("Application starting");
_logger.LogInformation("User login failed"); // Should be Warning
_logger.LogInformation("Database connection failed"); // Should be Error
_logger.LogInformation("Checking if user exists"); // Should be Debug/Trace

// Using Error for non-errors
_logger.LogError("User not found"); // Should be Warning or Information
```

**Correct**:

```csharp
// Trace - Very detailed, typically only enabled in development
_logger.LogTrace("Entering method {MethodName} with parameters {@Parameters}", 
    nameof(ProcessOrder), parameters);

// Debug - Useful for development/debugging
_logger.LogDebug("Loading configuration from {ConfigPath}", configPath);
_logger.LogDebug("Cache miss for key {CacheKey}", cacheKey);

// Information - Normal application flow, significant events
_logger.LogInformation("Order {OrderId} created successfully for {CustomerId}", 
    order.Id, customerId);
_logger.LogInformation("Application started. Environment: {Environment}", 
    env.EnvironmentName);

// Warning - Unexpected but handled situations
_logger.LogWarning("Retry attempt {Attempt} of {MaxAttempts} for {Operation}", 
    attempt, maxAttempts, "SendEmail");
_logger.LogWarning("Rate limit approaching for user {UserId}. Current: {Count}/{Limit}", 
    userId, count, limit);

// Error - Errors that are handled but indicate problems
_logger.LogError(exception, 
    "Failed to process payment for order {OrderId}. Will retry.", orderId);

// Critical - Application/system failures requiring immediate attention
_logger.LogCritical(exception, 
    "Database connection pool exhausted. Application cannot process requests.");
_logger.LogCritical("Security breach detected: {Details}", securityEvent);
```

**Why**:
- Enables proper filtering in production (Information and above)
- Allows verbose logging in development (Debug and Trace)
- Critical/Error can trigger alerts
- Makes log analysis efficient

---

### Rule 3: Implement Correlation IDs

**Priority**: High

**Description**: Add correlation IDs to track requests across services and log entries. Essential for debugging distributed systems.

**Incorrect**:

```csharp
// No correlation - impossible to trace requests
[HttpPost]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    _logger.LogInformation("Creating order");
    var order = await _orderService.CreateAsync(request);
    _logger.LogInformation("Order created");
    return Ok(order);
}

// Logs from different services can't be correlated
// Service A: "Sending message to queue"
// Service B: "Processing message" // Which message?
```

**Correct**:

```csharp
// Program.cs - Add correlation ID middleware
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICorrelationIdProvider, CorrelationIdProvider>();

// Correlation ID Provider
public interface ICorrelationIdProvider
{
    string CorrelationId { get; }
}

public class CorrelationIdProvider : ICorrelationIdProvider
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly string _correlationId;

    public CorrelationIdProvider(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
        _correlationId = GetOrCreateCorrelationId();
    }

    public string CorrelationId => _correlationId;

    private string GetOrCreateCorrelationId()
    {
        var context = _httpContextAccessor.HttpContext;
        
        if (context?.Request.Headers.TryGetValue("X-Correlation-ID", out var correlationId) == true
            && !string.IsNullOrWhiteSpace(correlationId))
        {
            return correlationId!;
        }

        return Activity.Current?.Id ?? Guid.NewGuid().ToString();
    }
}

// Correlation Middleware
public class CorrelationIdMiddleware
{
    private readonly RequestDelegate _next;

    public CorrelationIdMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context, ICorrelationIdProvider correlationProvider)
    {
        context.Response.Headers["X-Correlation-ID"] = correlationProvider.CorrelationId;
        
        using (LogContext.PushProperty("CorrelationId", correlationProvider.CorrelationId))
        {
            await _next(context);
        }
    }
}

// Or with Serilog enrichment in Program.cs
builder.Host.UseSerilog((context, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .Enrich.FromLogContext()
    .Enrich.WithCorrelationId()
    .Enrich.WithProperty("Application", "MyApi"));

// Now all logs automatically include CorrelationId
_logger.LogInformation("Order {OrderId} created", orderId);
// Output: {"CorrelationId": "abc-123", "OrderId": 456, "Message": "Order 456 created"}
```

**Why**:
- Trace requests across multiple services
- Debug issues by filtering all logs for a specific request
- Essential for microservices architecture
- Required for proper distributed tracing

---

### Rule 4: Avoid Logging Sensitive Data

**Priority**: Critical

**Description**: Never log passwords, tokens, credit card numbers, or other sensitive information.

**Incorrect**:

```csharp
// Logging sensitive authentication data
_logger.LogInformation("User login: {Username}, Password: {Password}", 
    request.Username, request.Password);

// Logging tokens
_logger.LogDebug("API call with token: {Token}", authToken);

// Logging payment details
_logger.LogInformation("Processing payment: {@PaymentRequest}", paymentRequest);
// PaymentRequest contains CardNumber, CVV, etc.

// Logging entire request bodies
_logger.LogDebug("Request body: {Body}", JsonSerializer.Serialize(request));
```

**Correct**:

```csharp
// Mask or exclude sensitive fields
_logger.LogInformation("User login attempt for {Username}", request.Username);

// Log only safe identifiers
_logger.LogDebug("API call for user {UserId}", userId);

// Use a sanitized DTO for logging
_logger.LogInformation("Processing payment: {@PaymentInfo}", new
{
    OrderId = paymentRequest.OrderId,
    Amount = paymentRequest.Amount,
    Currency = paymentRequest.Currency,
    CardLastFour = paymentRequest.CardNumber[^4..] // Last 4 digits only
});

// Configure Serilog to mask sensitive properties
public class SensitiveDataMaskingPolicy : IDestructuringPolicy
{
    private static readonly HashSet<string> SensitiveProperties = new(StringComparer.OrdinalIgnoreCase)
    {
        "Password", "Token", "Secret", "CardNumber", "CVV", "SSN", "ApiKey"
    };

    public bool TryDestructure(object value, ILogEventPropertyValueFactory factory, 
        out LogEventPropertyValue? result)
    {
        // Implementation to mask sensitive properties
    }
}

// Register in Program.cs
.Destructure.With<SensitiveDataMaskingPolicy>()
```

**Why**:
- Security compliance (PCI-DSS, GDPR, HIPAA)
- Logs are often stored long-term and accessed by many people
- Log aggregation systems may not have the same security as primary databases
- Prevents accidental data exposure

---

### Rule 5: Use Scoped Logging for Request Context

**Priority**: High

**Description**: Add contextual information that applies to all log entries within a scope, such as user ID, tenant ID, or operation name.

**Incorrect**:

```csharp
// Repeating context in every log statement
public async Task ProcessOrderAsync(int orderId, int userId)
{
    _logger.LogInformation("User {UserId} starting order {OrderId} processing", userId, orderId);
    _logger.LogDebug("User {UserId} validating order {OrderId}", userId, orderId);
    _logger.LogInformation("User {UserId} completed order {OrderId}", userId, orderId);
}
```

**Correct**:

```csharp
// Using scoped logging
public async Task ProcessOrderAsync(int orderId, int userId)
{
    using (_logger.BeginScope(new Dictionary<string, object>
    {
        ["OrderId"] = orderId,
        ["UserId"] = userId,
        ["Operation"] = "ProcessOrder"
    }))
    {
        _logger.LogInformation("Starting order processing");
        _logger.LogDebug("Validating order");
        
        await ValidateOrderAsync(orderId);
        
        _logger.LogInformation("Order processing completed");
    }
}

// With Serilog - LogContext
public async Task ProcessOrderAsync(int orderId, int userId)
{
    using (LogContext.PushProperty("OrderId", orderId))
    using (LogContext.PushProperty("UserId", userId))
    {
        Log.Information("Starting order processing");
        // All logs within this scope include OrderId and UserId
    }
}

// Middleware for request-level scope
public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public async Task InvokeAsync(HttpContext context)
    {
        var scope = new Dictionary<string, object>
        {
            ["RequestPath"] = context.Request.Path,
            ["RequestMethod"] = context.Request.Method,
            ["UserId"] = context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "anonymous"
        };

        using (_logger.BeginScope(scope))
        {
            await _next(context);
        }
    }
}
```

**Why**:
- DRY - don't repeat context in every log call
- Consistent context across all logs in a scope
- Easier to filter logs by context properties
- Cleaner, more readable code

---

### Rule 6: Configure Logging for Performance

**Priority**: High

**Description**: Avoid performance overhead from logging, especially in high-throughput scenarios.

**Incorrect**:

```csharp
// Expensive operations in log parameters
_logger.LogDebug("User profile: {Profile}", JsonSerializer.Serialize(user));

// String formatting regardless of log level
_logger.LogTrace($"Detailed state: {expensiveOperation.GetDetails()}");

// Logging in tight loops
foreach (var item in items) // Could be millions
{
    _logger.LogDebug("Processing item {ItemId}", item.Id);
    ProcessItem(item);
}
```

**Correct**:

```csharp
// Check log level before expensive operations
if (_logger.IsEnabled(LogLevel.Debug))
{
    _logger.LogDebug("User profile: {Profile}", JsonSerializer.Serialize(user));
}

// Use source generators for high-performance logging (.NET 6+)
public static partial class LoggerMessages
{
    [LoggerMessage(
        EventId = 1001,
        Level = LogLevel.Information,
        Message = "Order {OrderId} created for customer {CustomerId}")]
    public static partial void OrderCreated(
        this ILogger logger, int orderId, int customerId);

    [LoggerMessage(
        EventId = 1002,
        Level = LogLevel.Warning,
        Message = "Retry attempt {Attempt} for operation {Operation}")]
    public static partial void RetryAttempt(
        this ILogger logger, int attempt, string operation);

    [LoggerMessage(
        EventId = 2001,
        Level = LogLevel.Error,
        Message = "Failed to process order {OrderId}")]
    public static partial void OrderProcessingFailed(
        this ILogger logger, int orderId, Exception exception);
}

// Usage - zero allocation when log level is disabled
_logger.OrderCreated(order.Id, customerId);
_logger.OrderProcessingFailed(orderId, exception);

// Batch logging for loops
var processedIds = new List<int>();
foreach (var item in items)
{
    ProcessItem(item);
    processedIds.Add(item.Id);
}
_logger.LogDebug("Processed {Count} items: {ItemIds}", processedIds.Count, processedIds);

// Or log summary only
_logger.LogInformation("Batch processing completed. Processed: {Count}, Failed: {Failed}", 
    successCount, failCount);
```

**Why**:
- String interpolation happens even if log level is disabled
- Source generators eliminate boxing and allocation
- Reduces CPU and memory overhead
- Critical for high-throughput applications

---

### Rule 7: Configure Structured Output Format

**Priority**: Medium

**Description**: Configure logging to output JSON or another structured format for log aggregation systems.

**Incorrect**:

```csharp
// Default console output - not structured
// Output: info: MyApp.Services.OrderService[0]
//         Order 123 created for customer 456
```

**Correct**:

```csharp
// Program.cs - Serilog with JSON output
builder.Host.UseSerilog((context, services, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .ReadFrom.Services(services)
    .Enrich.FromLogContext()
    .Enrich.WithMachineName()
    .Enrich.WithEnvironmentName()
    .Enrich.WithProperty("Application", "OrderService")
    .WriteTo.Console(new RenderedCompactJsonFormatter())
    .WriteTo.Seq("http://localhost:5341")
    .WriteTo.ApplicationInsights(
        services.GetRequiredService<TelemetryConfiguration>(),
        TelemetryConverter.Traces));

// appsettings.json configuration
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.Hosting.Lifetime": "Information",
        "Microsoft.EntityFrameworkCore": "Warning",
        "System": "Warning"
      }
    },
    "WriteTo": [
      {
        "Name": "Console",
        "Args": {
          "formatter": "Serilog.Formatting.Compact.CompactJsonFormatter, Serilog.Formatting.Compact"
        }
      },
      {
        "Name": "File",
        "Args": {
          "path": "logs/log-.json",
          "rollingInterval": "Day",
          "formatter": "Serilog.Formatting.Compact.CompactJsonFormatter, Serilog.Formatting.Compact"
        }
      }
    ],
    "Enrich": ["FromLogContext", "WithMachineName", "WithThreadId"]
  }
}

// Output JSON:
// {"@t":"2024-01-15T10:30:00.000Z","@mt":"Order {OrderId} created","OrderId":123,
//  "CorrelationId":"abc-123","Application":"OrderService","MachineName":"server-01"}
```

**Why**:
- JSON is easily parsed by log aggregation tools
- Structured properties are queryable
- Consistent format across all services
- Enables advanced analytics and dashboards

---

## Integration Example

Complete logging setup for ASP.NET Core:

```csharp
// Program.cs
using Serilog;
using Serilog.Events;

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    Log.Information("Starting application");

    var builder = WebApplication.CreateBuilder(args);

    builder.Host.UseSerilog((context, services, config) => config
        .ReadFrom.Configuration(context.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Application", builder.Environment.ApplicationName)
        .Enrich.WithProperty("Environment", builder.Environment.EnvironmentName));

    // Add services
    builder.Services.AddControllers();
    builder.Services.AddHttpContextAccessor();

    var app = builder.Build();

    // Request logging middleware
    app.UseSerilogRequestLogging(options =>
    {
        options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        {
            diagnosticContext.Set("UserId", 
                httpContext.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "anonymous");
            diagnosticContext.Set("ClientIP", 
                httpContext.Connection.RemoteIpAddress?.ToString());
        };
    });

    app.UseRouting();
    app.UseAuthentication();
    app.UseAuthorization();
    app.MapControllers();

    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}

// Service with logging
public class OrderService
{
    private readonly ILogger<OrderService> _logger;
    private readonly AppDbContext _context;

    public OrderService(ILogger<OrderService> logger, AppDbContext context)
    {
        _logger = logger;
        _context = context;
    }

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        _logger.LogInformation(
            "Creating order for customer {CustomerId} with {ItemCount} items",
            request.CustomerId,
            request.Items.Count);

        try
        {
            var order = new Order
            {
                CustomerId = request.CustomerId,
                Items = request.Items.Select(i => new OrderItem
                {
                    ProductId = i.ProductId,
                    Quantity = i.Quantity
                }).ToList()
            };

            _context.Orders.Add(order);
            await _context.SaveChangesAsync();

            _logger.LogInformation(
                "Order {OrderId} created successfully. Total: {TotalAmount:C}",
                order.Id,
                order.TotalAmount);

            return order;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "Failed to create order for customer {CustomerId}",
                request.CustomerId);
            throw;
        }
    }
}
```

## Checklist

- [ ] Using message templates with named placeholders (not string interpolation)
- [ ] Appropriate log levels for different scenarios
- [ ] Correlation IDs implemented for request tracing
- [ ] Sensitive data excluded from logs
- [ ] Scoped logging for request context
- [ ] Log level checks before expensive operations
- [ ] Source generators for high-performance paths
- [ ] JSON output format configured
- [ ] Log aggregation tool configured (Seq, ELK, Application Insights)
- [ ] Microsoft/System namespaces filtered to Warning+

## References

- [Logging in .NET](https://docs.microsoft.com/dotnet/core/extensions/logging)
- [Serilog Documentation](https://serilog.net/)
- [High-performance logging](https://docs.microsoft.com/dotnet/core/extensions/high-performance-logging)
- [Structured Logging Best Practices](https://messagetemplates.org/)

## Changelog

### v1.0.0
- Initial release
- 7 core rules for structured logging
