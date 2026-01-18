---
name: api-rate-limiting
description: Best practices for implementing API rate limiting in ASP.NET Core to protect APIs from abuse, manage quotas, and ensure fair resource usage using built-in rate limiting and custom strategies.
version: 1.0.0
priority: medium
categories:
  - api
  - security
  - performance
use_when:
  - "When implementing rate limiting"
  - "When protecting APIs from abuse"
  - "When managing API quotas"
  - "When implementing throttling"
  - "When preventing DoS attacks"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.AspNetCore.RateLimiting"
related_skills:
  - webapi-best-practices
  - owasp-api-security
  - secure-headers
---

# API Rate Limiting Best Practices

## Overview

This skill covers implementing rate limiting in ASP.NET Core to protect APIs from abuse, manage quotas, and ensure fair resource usage. Rate limiting is essential for API security and performance. This skill addresses:

- Rate limiting strategies
- Per-user vs per-IP limiting
- Rate limit headers
- Distributed rate limiting
- Quota management

## Rules

### Rule 1: Implement Rate Limiting on All Endpoints

**Priority**: High

**Description**: Apply rate limiting to protect APIs from abuse and ensure fair usage.

**Incorrect**:

```csharp
// No rate limiting - vulnerable to abuse
[HttpPost("login")]
public async Task<IActionResult> Login(LoginRequest request)
{
    // Attacker can try millions of passwords
    var user = await _authService.ValidateAsync(request);
    return Ok(GenerateToken(user));
}

// Only some endpoints limited
[HttpPost("orders")]
[EnableRateLimiting("default")]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    // Limited
}

[HttpGet("products")]
public async Task<IActionResult> GetProducts()
{
    // Not limited - can be abused
}
```

**Correct**:

```csharp
// Configure rate limiting
builder.Services.AddRateLimiter(options =>
{
    // Global rate limiter
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User?.Identity?.Name ?? context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: partition => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));

    // Specific limiters
    options.AddFixedWindowLimiter("auth", limiterOptions =>
    {
        limiterOptions.PermitLimit = 5;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
        limiterOptions.QueueLimit = 0;
    });

    options.AddFixedWindowLimiter("api", limiterOptions =>
    {
        limiterOptions.PermitLimit = 100;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
        limiterOptions.QueueLimit = 0;
    });

    // Token bucket for burst traffic
    options.AddTokenBucketLimiter("expensive", limiterOptions =>
    {
        limiterOptions.TokenLimit = 10;
        limiterOptions.ReplenishmentPeriod = TimeSpan.FromMinutes(1);
        limiterOptions.TokensPerPeriod = 2;
        limiterOptions.AutoReplenishment = true;
    });

    // Sliding window
    options.AddSlidingWindowLimiter("sliding", limiterOptions =>
    {
        limiterOptions.PermitLimit = 50;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
        limiterOptions.SegmentsPerWindow = 4;
    });

    // Custom response
    options.OnRejected = async (context, token) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        context.HttpContext.Response.Headers.RetryAfter = "60";
        
        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            error = "Too many requests",
            message = "Rate limit exceeded. Please try again later.",
            retryAfter = 60
        }, token);
    };
});

var app = builder.Build();

// Apply globally
app.UseRateLimiter();

// Apply to specific endpoints
[HttpPost("login")]
[EnableRateLimiting("auth")]
public async Task<IActionResult> Login(LoginRequest request)
{
    // Limited to 5 requests per minute
}

[HttpPost("orders")]
[EnableRateLimiting("api")]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    // Limited to 100 requests per minute
}

[HttpGet("reports/generate")]
[EnableRateLimiting("expensive")]
public async Task<IActionResult> GenerateReport()
{
    // Token bucket: 10 tokens, 2 per minute
}
```

**Why**:
- Prevents brute force attacks
- Protects against DoS
- Fair resource allocation
- Better API stability
- Essential security

---

### Rule 2: Use Per-User Rate Limiting When Authenticated

**Priority**: High

**Description**: Apply different rate limits for authenticated vs anonymous users.

**Incorrect**:

```csharp
// Same limit for all users
options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
    RateLimitPartition.GetFixedWindowLimiter(
        partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
        factory: partition => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 100, // Same for everyone
            Window = TimeSpan.FromMinutes(1)
        }));
```

**Correct**:

```csharp
// Different limits for authenticated vs anonymous
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
    {
        var userId = context.User?.Identity?.Name;
        var isAuthenticated = context.User?.Identity?.IsAuthenticated == true;
        
        var partitionKey = isAuthenticated 
            ? $"user:{userId}" 
            : $"ip:{context.Connection.RemoteIpAddress}";

        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: partitionKey,
            factory: partition => new FixedWindowRateLimiterOptions
            {
                PermitLimit = isAuthenticated ? 1000 : 100, // Higher limit for authenticated
                Window = TimeSpan.FromMinutes(1),
                AutoReplenishment = true
            });
    });

    // Premium users get higher limits
    options.AddPolicy("premium", context =>
    {
        var isPremium = context.User?.IsInRole("Premium") == true;
        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: $"user:{context.User?.Identity?.Name}",
            factory: partition => new FixedWindowRateLimiterOptions
            {
                PermitLimit = isPremium ? 5000 : 1000,
                Window = TimeSpan.FromMinutes(1)
            });
    });
});

// Apply premium policy
[HttpPost("orders")]
[EnableRateLimiting("premium")]
public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
{
    // Premium users: 5000/min, Regular: 1000/min
}
```

**Why**:
- Fair usage policies
- Better user experience
- Tiered service levels
- Prevents abuse
- Business model support

---

### Rule 3: Include Rate Limit Headers in Responses

**Priority**: Medium

**Description**: Return rate limit information in response headers for client awareness.

**Incorrect**:

```csharp
// No rate limit headers
[HttpPost("orders")]
[EnableRateLimiting("api")]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    // Client doesn't know rate limit status
    return Ok(order);
}
```

**Correct**:

```csharp
// Custom rate limit policy with headers
public class CustomRateLimitPolicy : IRateLimiterPolicy<string>
{
    public Func<OnRejectedContext, CancellationToken, ValueTask>? OnRejected { get; }

    public RateLimitPartition<string> GetPartition(HttpContext httpContext)
    {
        var userId = httpContext.User?.Identity?.Name ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "anonymous";
        
        return RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: userId,
            factory: partition => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1),
                AutoReplenishment = true
            });
    }
}

// Middleware to add rate limit headers
public class RateLimitHeadersMiddleware
{
    private readonly RequestDelegate _next;

    public RateLimitHeadersMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        await _next(context);

        // Add rate limit headers (if available from rate limiter)
        var rateLimitFeature = context.Features.Get<IRateLimiterFeature>();
        if (rateLimitFeature != null)
        {
            context.Response.Headers["X-RateLimit-Limit"] = "100";
            context.Response.Headers["X-RateLimit-Remaining"] = rateLimitFeature.RemainingPermits?.ToString() ?? "unknown";
            context.Response.Headers["X-RateLimit-Reset"] = DateTimeOffset.UtcNow.AddMinutes(1).ToUnixTimeSeconds().ToString();
        }
    }
}

// Register middleware
app.UseMiddleware<RateLimitHeadersMiddleware>();
app.UseRateLimiter();

// Response headers:
// X-RateLimit-Limit: 100
// X-RateLimit-Remaining: 95
// X-RateLimit-Reset: 1704067200
// Retry-After: 60 (when rate limited)
```

**Why**:
- Client awareness of limits
- Better UX
- Standard headers
- Prevents unnecessary requests
- Industry practice

---

### Rule 4: Use Distributed Rate Limiting for Multi-Server

**Priority**: Medium

**Description**: Use distributed rate limiting when deploying multiple server instances.

**Incorrect**:

```csharp
// In-memory rate limiting - doesn't work across servers
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: partition => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1)
            }));
});
// Each server has separate limit - user can make 100 * server_count requests
```

**Correct**:

```csharp
// Distributed rate limiting with Redis
// Install: AspNetCoreRateLimit.Redis

builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
});

builder.Services.AddRateLimiter(options =>
{
    // Use Redis-backed rate limiter
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
    {
        var redis = context.RequestServices.GetRequiredService<IDistributedCache>();
        var partitionKey = context.User?.Identity?.Name ?? context.Connection.RemoteIpAddress?.ToString() ?? "anonymous";
        
        return RateLimitPartition.GetRedisFixedWindowLimiter(
            partitionKey: partitionKey,
            factory: (partition, redis) => new RedisFixedWindowRateLimiterOptions
            {
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1),
                ConnectionMultiplexerFactory = () => ConnectionMultiplexer.Connect(redisConnectionString)
            });
    });
});

// Or use dedicated rate limiting library
// Install: AspNetCoreRateLimit

builder.Services.AddMemoryCache();
builder.Services.Configure<IpRateLimitOptions>(builder.Configuration.GetSection("IpRateLimiting"));
builder.Services.AddInMemoryRateLimiting();
builder.Services.AddSingleton<IRateLimitConfiguration, RateLimitConfiguration>();

var app = builder.Build();
app.UseIpRateLimiting();
```

**Why**:
- Works across multiple servers
- Consistent rate limiting
- Prevents limit bypass
- Production requirement
- Better scalability

---

### Rule 5: Configure Different Limits for Different Endpoints

**Priority**: High

**Description**: Apply stricter limits to expensive or sensitive endpoints.

**Correct**:

```csharp
builder.Services.AddRateLimiter(options =>
{
    // Authentication endpoints - very strict
    options.AddFixedWindowLimiter("auth", limiterOptions =>
    {
        limiterOptions.PermitLimit = 5;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
        limiterOptions.QueueLimit = 0;
    });

    // Regular API endpoints
    options.AddFixedWindowLimiter("api", limiterOptions =>
    {
        limiterOptions.PermitLimit = 100;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
    });

    // Expensive operations - token bucket
    options.AddTokenBucketLimiter("expensive", limiterOptions =>
    {
        limiterOptions.TokenLimit = 10;
        limiterOptions.ReplenishmentPeriod = TimeSpan.FromMinutes(1);
        limiterOptions.TokensPerPeriod = 2; // 2 requests per minute
        limiterOptions.AutoReplenishment = true;
    });

    // File uploads - sliding window
    options.AddSlidingWindowLimiter("upload", limiterOptions =>
    {
        limiterOptions.PermitLimit = 20;
        limiterOptions.Window = TimeSpan.FromMinutes(5);
        limiterOptions.SegmentsPerWindow = 5;
    });
});

// Apply to endpoints
[HttpPost("login")]
[EnableRateLimiting("auth")] // 5 per minute
public async Task<IActionResult> Login(LoginRequest request) { }

[HttpPost("orders")]
[EnableRateLimiting("api")] // 100 per minute
public async Task<IActionResult> CreateOrder(CreateOrderRequest request) { }

[HttpPost("reports/generate")]
[EnableRateLimiting("expensive")] // 2 per minute (token bucket)
public async Task<IActionResult> GenerateReport() { }

[HttpPost("files/upload")]
[EnableRateLimiting("upload")] // 20 per 5 minutes (sliding window)
public async Task<IActionResult> UploadFile(IFormFile file) { }
```

**Why**:
- Protects expensive operations
- Prevents resource exhaustion
- Fair resource allocation
- Better API design
- Security best practice

---

## Integration Example

Complete rate limiting setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRateLimiter(options =>
{
    // Global limiter
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User?.Identity?.Name ?? context.Connection.RemoteIpAddress?.ToString() ?? "anonymous",
            factory: partition => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1)
            }));

    // Auth limiter
    options.AddFixedWindowLimiter("auth", limiterOptions =>
    {
        limiterOptions.PermitLimit = 5;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
    });
});

var app = builder.Build();

app.UseRateLimiter();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] Rate limiting configured
- [ ] Different limits for different endpoints
- [ ] Per-user limiting for authenticated users
- [ ] Rate limit headers included
- [ ] Distributed rate limiting (if multi-server)
- [ ] Custom error responses
- [ ] Retry-After header set
- [ ] Limits appropriate for endpoint type

## References

- [Rate Limiting](https://docs.microsoft.com/aspnet/core/performance/rate-limit)
- [Rate Limiting Middleware](https://docs.microsoft.com/aspnet/core/performance/rate-limit#rate-limit-middleware)

## Changelog

### v1.0.0
- Initial release
- 5 core rules for API rate limiting
