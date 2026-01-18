---
name: middleware-patterns
description: Best practices for creating and using middleware in ASP.NET Core including custom middleware, pipeline ordering, conditional middleware, and cross-cutting concerns.
version: 1.0.0
priority: medium
categories:
  - patterns
  - middleware
use_when:
  - "When creating custom middleware"
  - "When ordering middleware pipeline"
  - "When implementing cross-cutting concerns"
  - "When adding request/response processing"
  - "When implementing custom authentication/authorization"
prerequisites:
  - "ASP.NET Core 8.0+"
related_skills:
  - error-handling-patterns
  - structured-logging
  - secure-headers
---

# Middleware Patterns Best Practices

## Overview

This skill covers best practices for creating and using middleware in ASP.NET Core. Middleware is essential for implementing cross-cutting concerns like logging, authentication, and error handling. This skill addresses:

- Middleware pipeline ordering
- Custom middleware patterns
- Request/response modification
- Conditional middleware
- Performance considerations
- Middleware lifecycle

## Rules

### Rule 1: Order Middleware Correctly

**Priority**: Critical

**Description**: Middleware order matters. Place middleware in the correct order for proper execution.

**Incorrect**:

```csharp
// Wrong order - authentication before exception handling
var app = builder.Build();

app.UseAuthentication(); // Runs before exception handler
app.UseExceptionHandler(); // Exceptions in auth won't be caught properly

app.UseRouting();
app.UseAuthorization(); // Should be after UseAuthentication
app.UseEndpoints(endpoints => endpoints.MapControllers());
```

**Correct**:

```csharp
// Correct middleware order
var app = builder.Build();

// 1. Exception handling (first - catches all exceptions)
app.UseExceptionHandler();

// 2. HTTPS redirection
app.UseHttpsRedirection();

// 3. Static files (before routing)
app.UseStaticFiles();

// 4. Routing (before authentication)
app.UseRouting();

// 5. CORS (before authentication)
app.UseCors("Production");

// 6. Authentication (before authorization)
app.UseAuthentication();

// 7. Authorization (after authentication)
app.UseAuthorization();

// 8. Rate limiting (after auth, before endpoints)
app.UseRateLimiter();

// 9. Endpoints (last)
app.MapControllers();

app.Run();

// Recommended order:
// 1. Exception handling
// 2. HTTPS redirection
// 3. Static files
// 4. Routing
// 5. CORS
// 6. Authentication
// 7. Authorization
// 8. Rate limiting
// 9. Endpoints
```

**Why**:
- Middleware executes in order
- Wrong order causes bugs
- Security middleware must be early
- Exception handling must be first
- Critical for proper functionality

---

### Rule 2: Create Reusable Middleware

**Priority**: High

**Description**: Create reusable middleware classes instead of inline middleware.

**Incorrect**:

```csharp
// Inline middleware - not reusable, hard to test
app.Use(async (context, next) =>
{
    var correlationId = context.Request.Headers["X-Correlation-ID"].FirstOrDefault()
        ?? Guid.NewGuid().ToString();
    
    context.Response.Headers["X-Correlation-ID"] = correlationId;
    context.Items["CorrelationId"] = correlationId;
    
    await next();
});

// More inline middleware
app.Use(async (context, next) =>
{
    var stopwatch = Stopwatch.StartNew();
    await next();
    stopwatch.Stop();
    context.Response.Headers["X-Response-Time"] = stopwatch.ElapsedMilliseconds.ToString();
});
```

**Correct**:

```csharp
// Reusable middleware class
public class CorrelationIdMiddleware
{
    private readonly RequestDelegate _next;
    private const string CorrelationIdHeader = "X-Correlation-ID";
    private const string CorrelationIdItemKey = "CorrelationId";

    public CorrelationIdMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = context.Request.Headers[CorrelationIdHeader].FirstOrDefault()
            ?? Guid.NewGuid().ToString();

        context.Response.Headers[CorrelationIdHeader] = correlationId;
        context.Items[CorrelationIdItemKey] = correlationId;

        await _next(context);
    }
}

// Extension method for easy registration
public static class CorrelationIdMiddlewareExtensions
{
    public static IApplicationBuilder UseCorrelationId(this IApplicationBuilder builder)
    {
        return builder.UseMiddleware<CorrelationIdMiddleware>();
    }
}

// Usage
app.UseCorrelationId();

// Performance monitoring middleware
public class PerformanceMonitoringMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<PerformanceMonitoringMiddleware> _logger;

    public PerformanceMonitoringMiddleware(
        RequestDelegate next,
        ILogger<PerformanceMonitoringMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var stopwatch = Stopwatch.StartNew();
        
        try
        {
            await _next(context);
        }
        finally
        {
            stopwatch.Stop();
            var elapsedMs = stopwatch.ElapsedMilliseconds;
            
            context.Response.Headers["X-Response-Time"] = $"{elapsedMs}ms";
            
            if (elapsedMs > 1000)
            {
                _logger.LogWarning(
                    "Slow request: {Method} {Path} took {ElapsedMs}ms",
                    context.Request.Method,
                    context.Request.Path,
                    elapsedMs);
            }
        }
    }
}

// Register
app.UseMiddleware<PerformanceMonitoringMiddleware>();
```

**Why**:
- Reusable across projects
- Testable middleware
- Better organization
- Easier to maintain
- Professional pattern

---

### Rule 3: Use Conditional Middleware

**Priority**: Medium

**Description**: Apply middleware conditionally based on request path or environment.

**Incorrect**:

```csharp
// Middleware runs for all requests
app.UseSwagger();
app.UseSwaggerUI(); // Should only run in development

// No path filtering
app.UseAuthentication(); // Runs for static files too
```

**Correct**:

```csharp
// Conditional middleware
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Path-based conditional middleware
app.UseWhen(context => context.Request.Path.StartsWithSegments("/api"), appBuilder =>
{
    appBuilder.UseAuthentication();
    appBuilder.UseAuthorization();
    appBuilder.UseRateLimiter();
});

// Or use MapWhen
app.MapWhen(context => context.Request.Path.StartsWithSegments("/api"), appBuilder =>
{
    appBuilder.UseAuthentication();
    appBuilder.UseAuthorization();
    appBuilder.UseRateLimiter();
    appBuilder.UseEndpoints(endpoints => endpoints.MapControllers());
});

// Static files without auth
app.MapWhen(context => !context.Request.Path.StartsWithSegments("/api"), appBuilder =>
{
    appBuilder.UseStaticFiles();
});

// Health checks without auth
app.Map("/health", appBuilder =>
{
    appBuilder.UseHealthChecks();
});

// Or in middleware itself
public class ApiAuthMiddleware
{
    private readonly RequestDelegate _next;

    public ApiAuthMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Only apply to API routes
        if (context.Request.Path.StartsWithSegments("/api"))
        {
            // Auth logic
        }

        await _next(context);
    }
}
```

**Why**:
- Better performance
- Security (auth only where needed)
- Flexible middleware application
- Environment-specific behavior
- Optimized pipeline

---

### Rule 4: Handle Middleware Dependencies

**Priority**: High

**Description**: Inject dependencies correctly in middleware using constructor injection.

**Incorrect**:

```csharp
// Service locator in middleware
public class LoggingMiddleware
{
    private readonly RequestDelegate _next;

    public LoggingMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var logger = context.RequestServices.GetRequiredService<ILogger<LoggingMiddleware>>(); // Service locator
        logger.LogInformation("Request: {Path}", context.Request.Path);
        await _next(context);
    }
}
```

**Correct**:

```csharp
// Constructor injection
public class LoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<LoggingMiddleware> _logger;

    public LoggingMiddleware(
        RequestDelegate next,
        ILogger<LoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        _logger.LogInformation("Request: {Method} {Path}", 
            context.Request.Method, 
            context.Request.Path);
        
        await _next(context);
    }
}

// Multiple dependencies
public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;
    private readonly ICorrelationIdProvider _correlationProvider;

    public RequestLoggingMiddleware(
        RequestDelegate next,
        ILogger<RequestLoggingMiddleware> logger,
        ICorrelationIdProvider correlationProvider)
    {
        _next = next;
        _logger = logger;
        _correlationProvider = correlationProvider;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        using var scope = _logger.BeginScope(new Dictionary<string, object>
        {
            ["CorrelationId"] = _correlationProvider.CorrelationId,
            ["RequestPath"] = context.Request.Path
        });

        _logger.LogInformation("Processing request");
        await _next(context);
        _logger.LogInformation("Request completed with status {StatusCode}", 
            context.Response.StatusCode);
    }
}
```

**Why**:
- Explicit dependencies
- Testable middleware
- No service locator
- Better design
- DI best practices

---

### Rule 5: Modify Request/Response Carefully

**Priority**: High

**Description**: Be careful when modifying request/response streams. They can only be read once.

**Incorrect**:

```csharp
// Reading request body multiple times
public async Task InvokeAsync(HttpContext context)
{
    // Enable buffering to read body
    context.Request.EnableBuffering();
    
    var body = await new StreamReader(context.Request.Body).ReadToEndAsync();
    context.Request.Body.Position = 0; // Reset position
    
    // Log body
    _logger.LogInformation("Request body: {Body}", body);
    
    // Read again - might work, but error-prone
    var body2 = await new StreamReader(context.Request.Body).ReadToEndAsync();
    
    await _next(context);
}
```

**Correct**:

```csharp
// Safe request body reading
public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public async Task InvokeAsync(HttpContext context)
    {
        // Enable buffering
        context.Request.EnableBuffering();
        
        // Read body once
        using var reader = new StreamReader(
            context.Request.Body,
            encoding: Encoding.UTF8,
            leaveOpen: true);
        
        var body = await reader.ReadToEndAsync();
        context.Request.Body.Position = 0; // Reset for next middleware

        // Log (be careful with sensitive data)
        if (!IsSensitivePath(context.Request.Path))
        {
            _logger.LogDebug("Request body: {Body}", body);
        }

        await _next(context);
    }

    private static bool IsSensitivePath(PathString path)
    {
        return path.StartsWithSegments("/api/auth/login") ||
               path.StartsWithSegments("/api/auth/register");
    }
}

// Response modification
public class ResponseModificationMiddleware
{
    private readonly RequestDelegate _next;

    public async Task InvokeAsync(HttpContext context)
    {
        var originalBodyStream = context.Response.Body;
        
        using var responseBody = new MemoryStream();
        context.Response.Body = responseBody;

        await _next(context);

        // Modify response if needed
        if (context.Response.ContentType?.Contains("application/json") == true)
        {
            responseBody.Seek(0, SeekOrigin.Begin);
            var responseBodyText = await new StreamReader(responseBody).ReadToEndAsync();
            
            // Modify JSON if needed
            var modifiedResponse = ModifyResponse(responseBodyText);
            
            var modifiedBytes = Encoding.UTF8.GetBytes(modifiedResponse);
            await originalBodyStream.WriteAsync(modifiedBytes, 0, modifiedBytes.Length);
        }
        else
        {
            await responseBody.CopyToAsync(originalBodyStream);
        }
    }
}
```

**Why**:
- Streams can only be read once
- Proper buffering needed
- Memory management
- Prevents errors
- Safe stream handling

---

### Rule 6: Use Middleware for Cross-Cutting Concerns

**Priority**: High

**Description**: Use middleware for concerns that apply to multiple endpoints.

**Incorrect**:

```csharp
// Repeating logic in every controller
[ApiController]
public class OrdersController : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
    {
        // Correlation ID logic
        var correlationId = Request.Headers["X-Correlation-ID"].FirstOrDefault()
            ?? Guid.NewGuid().ToString();
        Response.Headers["X-Correlation-ID"] = correlationId;
        
        // Logging logic
        _logger.LogInformation("Creating order");
        
        // Timing logic
        var stopwatch = Stopwatch.StartNew();
        var order = await _service.CreateAsync(request);
        stopwatch.Stop();
        Response.Headers["X-Response-Time"] = stopwatch.ElapsedMilliseconds.ToString();
        
        return Ok(order);
    }
    // Repeated in every action
}
```

**Correct**:

```csharp
// Middleware for cross-cutting concerns
public class RequestContextMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestContextMiddleware> _logger;

    public async Task InvokeAsync(HttpContext context)
    {
        // Correlation ID
        var correlationId = context.Request.Headers["X-Correlation-ID"].FirstOrDefault()
            ?? Guid.NewGuid().ToString();
        context.Response.Headers["X-Correlation-ID"] = correlationId;
        context.Items["CorrelationId"] = correlationId;

        // Request logging
        _logger.LogInformation(
            "Request: {Method} {Path} [CorrelationId: {CorrelationId}]",
            context.Request.Method,
            context.Request.Path,
            correlationId);

        // Performance monitoring
        var stopwatch = Stopwatch.StartNew();
        await _next(context);
        stopwatch.Stop();

        context.Response.Headers["X-Response-Time"] = $"{stopwatch.ElapsedMilliseconds}ms";

        _logger.LogInformation(
            "Response: {StatusCode} in {ElapsedMs}ms [CorrelationId: {CorrelationId}]",
            context.Response.StatusCode,
            stopwatch.ElapsedMilliseconds,
            correlationId);
    }
}

// Register once
app.UseMiddleware<RequestContextMiddleware>();

// Controllers are clean
[ApiController]
public class OrdersController : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
    {
        var order = await _service.CreateAsync(request);
        return Ok(order);
        // Cross-cutting concerns handled by middleware
    }
}
```

**Why**:
- DRY principle
- Consistent behavior
- Easier maintenance
- Cleaner controllers
- Centralized logic

---

## Integration Example

Complete middleware setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

var app = builder.Build();

// Middleware pipeline (correct order)
app.UseExceptionHandler();

app.UseHttpsRedirection();

app.UseStaticFiles();

app.UseRouting();

app.UseCors("Production");

app.UseAuthentication();
app.UseAuthorization();

app.UseRateLimiter();

// Custom middleware
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseMiddleware<RequestLoggingMiddleware>();
app.UseMiddleware<PerformanceMonitoringMiddleware>();

app.MapControllers();

app.Run();
```

## Checklist

- [ ] Middleware ordered correctly
- [ ] Reusable middleware classes created
- [ ] Conditional middleware used when needed
- [ ] Dependencies injected via constructor
- [ ] Request/response streams handled safely
- [ ] Cross-cutting concerns in middleware
- [ ] Middleware is testable
- [ ] Performance considered

## References

- [Middleware](https://docs.microsoft.com/aspnet/core/fundamentals/middleware/)
- [Custom Middleware](https://docs.microsoft.com/aspnet/core/fundamentals/middleware/write)
- [Middleware Ordering](https://docs.microsoft.com/aspnet/core/fundamentals/middleware/#middleware-order)

## Changelog

### v1.0.0
- Initial release
- 6 core rules for middleware patterns
