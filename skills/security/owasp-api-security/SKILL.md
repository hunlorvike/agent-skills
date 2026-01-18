---
name: owasp-api-security
description: Security best practices based on OWASP API Security Top 10, covering authentication, authorization, data exposure, rate limiting, and injection prevention for ASP.NET Core APIs.
version: 1.0.0
priority: critical
categories:
  - security
  - api
  - owasp
use_when:
  - "When reviewing API security"
  - "When implementing new endpoints"
  - "When preparing for security audits"
  - "When handling sensitive data"
  - "When securing production APIs"
prerequisites:
  - "ASP.NET Core 8.0+"
related_skills:
  - jwt-authentication
  - input-validation
  - secure-headers
---

# OWASP API Security Best Practices

## Overview

This skill covers the OWASP API Security Top 10 risks and how to mitigate them in ASP.NET Core. API security vulnerabilities can lead to data breaches, unauthorized access, and system compromise. This skill addresses:

- Broken Authentication
- Broken Authorization (BOLA/BFLA)
- Excessive Data Exposure
- Lack of Resources & Rate Limiting
- Injection Attacks
- Mass Assignment

## Rules

### Rule 1: Prevent Broken Object Level Authorization (BOLA)

**Priority**: Critical

**Description**: Always verify that the authenticated user has permission to access the requested resource. Don't rely only on authentication.

**Incorrect**:

```csharp
// Vulnerable: No ownership check
[Authorize]
[HttpGet("orders/{id}")]
public async Task<ActionResult<Order>> GetOrder(int id)
{
    var order = await _context.Orders.FindAsync(id);
    if (order == null)
        return NotFound();
    
    return Ok(order); // Any authenticated user can access any order!
}

// Vulnerable: Only checking authentication
[Authorize]
[HttpPut("users/{id}/profile")]
public async Task<IActionResult> UpdateProfile(int id, UpdateProfileRequest request)
{
    var user = await _context.Users.FindAsync(id);
    user.Name = request.Name; // Any user can update any profile!
    await _context.SaveChangesAsync();
    return NoContent();
}
```

**Correct**:

```csharp
// Secure: Verify ownership
[Authorize]
[HttpGet("orders/{id}")]
public async Task<ActionResult<OrderDto>> GetOrder(int id)
{
    var userId = GetCurrentUserId();
    
    var order = await _context.Orders
        .Where(o => o.Id == id)
        .Where(o => o.UserId == userId || User.IsInRole("Admin")) // Authorization check
        .Select(o => new OrderDto { /* ... */ })
        .FirstOrDefaultAsync();

    if (order == null)
        return NotFound(); // Same response whether not found or forbidden

    return Ok(order);
}

// Secure: Use resource-based authorization
[Authorize]
[HttpPut("users/{id}/profile")]
public async Task<IActionResult> UpdateProfile(int id, UpdateProfileRequest request)
{
    var currentUserId = GetCurrentUserId();
    
    // Users can only update their own profile
    if (id != currentUserId && !User.IsInRole("Admin"))
        return Forbid();

    var user = await _context.Users.FindAsync(id);
    if (user == null)
        return NotFound();

    user.Name = request.Name;
    await _context.SaveChangesAsync();
    return NoContent();
}

// Using IAuthorizationService for complex scenarios
public class OrderAuthorizationHandler : AuthorizationHandler<OwnerRequirement, Order>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        OwnerRequirement requirement,
        Order resource)
    {
        var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        
        if (resource.UserId.ToString() == userId || 
            context.User.IsInRole("Admin"))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}

// Controller using IAuthorizationService
[HttpDelete("orders/{id}")]
public async Task<IActionResult> DeleteOrder(int id)
{
    var order = await _context.Orders.FindAsync(id);
    if (order == null)
        return NotFound();

    var authResult = await _authorizationService
        .AuthorizeAsync(User, order, "OwnerPolicy");

    if (!authResult.Succeeded)
        return Forbid();

    _context.Orders.Remove(order);
    await _context.SaveChangesAsync();
    return NoContent();
}

private int GetCurrentUserId() =>
    int.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "0");
```

**Why**:
- BOLA is the #1 API vulnerability (OWASP API Top 10)
- Authentication != Authorization
- Users should only access their own resources
- Admins may have elevated access

---

### Rule 2: Prevent Mass Assignment

**Priority**: Critical

**Description**: Never bind request data directly to domain entities. Use DTOs with explicit allowed properties.

**Incorrect**:

```csharp
// Vulnerable: Binding directly to entity
[HttpPost("users")]
public async Task<IActionResult> CreateUser([FromBody] User user)
{
    // Attacker could include: { "name": "John", "isAdmin": true }
    _context.Users.Add(user);
    await _context.SaveChangesAsync();
    return Ok(user);
}

// Vulnerable: Using dynamic/ExpandoObject
[HttpPut("products/{id}")]
public async Task<IActionResult> UpdateProduct(int id, [FromBody] dynamic product)
{
    var existing = await _context.Products.FindAsync(id);
    // Dangerous - any property can be modified
    existing.Name = product.Name;
    existing.Price = product.Price;
    // Attacker could set: existing.Cost = 0.01;
    await _context.SaveChangesAsync();
    return Ok();
}
```

**Correct**:

```csharp
// Secure: Use explicit DTOs
public record CreateUserRequest
{
    [Required]
    [StringLength(100)]
    public required string Name { get; init; }

    [Required]
    [EmailAddress]
    public required string Email { get; init; }

    // Note: NO IsAdmin property - users can't set their own admin status
}

[HttpPost("users")]
public async Task<ActionResult<UserDto>> CreateUser([FromBody] CreateUserRequest request)
{
    var user = new User
    {
        Name = request.Name,
        Email = request.Email,
        IsAdmin = false, // Explicitly set by server
        CreatedAt = DateTime.UtcNow
    };

    _context.Users.Add(user);
    await _context.SaveChangesAsync();

    return CreatedAtAction(nameof(GetUser), new { id = user.Id }, MapToDto(user));
}

// Secure: Explicit property mapping
public record UpdateProductRequest
{
    [Required]
    [StringLength(200)]
    public required string Name { get; init; }

    [Range(0.01, 999999.99)]
    public decimal Price { get; init; }

    [StringLength(2000)]
    public string? Description { get; init; }
    
    // Note: NO Cost, SupplierId, or other sensitive fields
}

[HttpPut("products/{id}")]
public async Task<IActionResult> UpdateProduct(int id, [FromBody] UpdateProductRequest request)
{
    var product = await _context.Products.FindAsync(id);
    if (product == null)
        return NotFound();

    // Explicit mapping - only allowed fields
    product.Name = request.Name;
    product.Price = request.Price;
    product.Description = request.Description;
    product.UpdatedAt = DateTime.UtcNow;

    await _context.SaveChangesAsync();
    return NoContent();
}

// Or use AutoMapper with explicit configuration
public class ProductMappingProfile : Profile
{
    public ProductMappingProfile()
    {
        CreateMap<UpdateProductRequest, Product>()
            .ForMember(dest => dest.Id, opt => opt.Ignore())
            .ForMember(dest => dest.Cost, opt => opt.Ignore())
            .ForMember(dest => dest.SupplierId, opt => opt.Ignore())
            .ForMember(dest => dest.CreatedAt, opt => opt.Ignore());
    }
}
```

**Why**:
- Attackers can add extra fields in JSON requests
- Binding to entities allows setting any property
- DTOs whitelist allowed properties
- Prevents privilege escalation

---

### Rule 3: Prevent Excessive Data Exposure

**Priority**: High

**Description**: Return only the data the client needs. Never return entire entities with sensitive fields.

**Incorrect**:

```csharp
// Vulnerable: Returning entire entity
[HttpGet("users/{id}")]
public async Task<ActionResult<User>> GetUser(int id)
{
    return await _context.Users
        .Include(u => u.Orders)
        .Include(u => u.PaymentMethods)
        .FirstOrDefaultAsync(u => u.Id == id);
    // Exposes: PasswordHash, SecurityStamp, PaymentMethods, etc.
}

// Vulnerable: Including sensitive data in lists
[HttpGet("users")]
public async Task<ActionResult<List<User>>> GetUsers()
{
    return await _context.Users.ToListAsync();
    // Every user's sensitive data exposed
}
```

**Correct**:

```csharp
// Secure: Return only needed data
public record UserDto
{
    public int Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public string Email { get; init; } = string.Empty;
    public DateTime CreatedAt { get; init; }
    // Note: NO PasswordHash, SecurityStamp, etc.
}

public record UserDetailDto : UserDto
{
    public string? PhoneNumber { get; init; }
    public AddressDto? Address { get; init; }
    // Only non-sensitive additional details
}

[HttpGet("users/{id}")]
public async Task<ActionResult<UserDetailDto>> GetUser(int id)
{
    var user = await _context.Users
        .Where(u => u.Id == id)
        .Select(u => new UserDetailDto
        {
            Id = u.Id,
            Name = u.Name,
            Email = u.Email,
            CreatedAt = u.CreatedAt,
            PhoneNumber = u.PhoneNumber,
            Address = u.Address != null ? new AddressDto
            {
                City = u.Address.City,
                Country = u.Address.Country
                // Exclude street address for privacy
            } : null
        })
        .FirstOrDefaultAsync();

    if (user == null)
        return NotFound();

    return Ok(user);
}

// Secure: Different DTOs for different audiences
public record UserPublicDto  // For public profile
{
    public int Id { get; init; }
    public string Name { get; init; } = string.Empty;
}

public record UserAdminDto : UserDto  // For admin view
{
    public bool IsLocked { get; init; }
    public int LoginAttempts { get; init; }
    public DateTime? LastLoginAt { get; init; }
}

[HttpGet("users")]
public async Task<ActionResult<List<UserDto>>> GetUsers()
{
    var isAdmin = User.IsInRole("Admin");

    if (isAdmin)
    {
        return Ok(await _context.Users
            .Select(u => new UserAdminDto { /* admin fields */ })
            .ToListAsync());
    }

    return Ok(await _context.Users
        .Select(u => new UserPublicDto { Id = u.Id, Name = u.Name })
        .ToListAsync());
}
```

**Why**:
- Reduces attack surface
- Prevents accidental data leakage
- Improves performance (less data transferred)
- Compliance with data minimization principles

---

### Rule 4: Implement Rate Limiting

**Priority**: High

**Description**: Protect APIs from abuse with rate limiting. Prevent brute force attacks and denial of service.

**Incorrect**:

```csharp
// Vulnerable: No rate limiting
[HttpPost("login")]
public async Task<IActionResult> Login(LoginRequest request)
{
    // Attacker can try millions of passwords
    var user = await _authService.ValidateAsync(request);
    if (user == null)
        return Unauthorized();
    return Ok(GenerateToken(user));
}

// Vulnerable: Expensive operation without limits
[HttpGet("reports/generate")]
public async Task<IActionResult> GenerateReport()
{
    // Can be called repeatedly, overloading the server
    var report = await _reportService.GenerateExpensiveReportAsync();
    return Ok(report);
}
```

**Correct**:

```csharp
// Program.cs - Configure rate limiting
builder.Services.AddRateLimiter(options =>
{
    // Global rate limit
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User?.Identity?.Name ?? context.Request.Headers.Host.ToString(),
            factory: partition => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 100,
                Window = TimeSpan.FromMinutes(1)
            }));

    // Specific limiter for auth endpoints
    options.AddFixedWindowLimiter("auth", options =>
    {
        options.PermitLimit = 5;
        options.Window = TimeSpan.FromMinutes(1);
        options.QueueLimit = 0;
    });

    // Stricter limiter for expensive operations
    options.AddTokenBucketLimiter("expensive", options =>
    {
        options.TokenLimit = 10;
        options.ReplenishmentPeriod = TimeSpan.FromMinutes(1);
        options.TokensPerPeriod = 2;
    });

    // Custom response
    options.OnRejected = async (context, token) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        context.HttpContext.Response.Headers.RetryAfter = "60";
        
        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            error = "Too many requests",
            retryAfter = 60
        }, token);
    };
});

// Use rate limiting middleware
app.UseRateLimiter();

// Apply to specific endpoints
[HttpPost("login")]
[EnableRateLimiting("auth")]
public async Task<IActionResult> Login(LoginRequest request)
{
    var user = await _authService.ValidateAsync(request);
    if (user == null)
    {
        // Log failed attempt
        _logger.LogWarning("Failed login attempt for {Email} from {IP}",
            request.Email, HttpContext.Connection.RemoteIpAddress);
        return Unauthorized();
    }
    return Ok(GenerateToken(user));
}

[HttpGet("reports/generate")]
[Authorize]
[EnableRateLimiting("expensive")]
public async Task<IActionResult> GenerateReport()
{
    var report = await _reportService.GenerateExpensiveReportAsync();
    return Ok(report);
}

// Disable for health checks
[HttpGet("health")]
[DisableRateLimiting]
public IActionResult Health() => Ok();
```

**Why**:
- Prevents brute force password attacks
- Protects against DoS attacks
- Reduces server load from abusive clients
- Fair resource allocation

---

### Rule 5: Prevent Injection Attacks

**Priority**: Critical

**Description**: Never concatenate user input into queries. Use parameterized queries and ORMs properly.

**Incorrect**:

```csharp
// SQL Injection vulnerability
[HttpGet("products/search")]
public async Task<IActionResult> SearchProducts(string name)
{
    var sql = $"SELECT * FROM Products WHERE Name LIKE '%{name}%'";
    var products = await _context.Products.FromSqlRaw(sql).ToListAsync();
    return Ok(products);
    // Attacker: name = "'; DROP TABLE Products; --"
}

// Command injection
[HttpPost("execute")]
public IActionResult ExecuteCommand(string command)
{
    var process = Process.Start("cmd.exe", $"/c {command}");
    return Ok();
}

// LDAP injection
public async Task<User?> FindUser(string username)
{
    var filter = $"(uid={username})"; // Dangerous!
    return await _ldapService.SearchAsync(filter);
}
```

**Correct**:

```csharp
// Secure: Parameterized query with EF Core
[HttpGet("products/search")]
public async Task<ActionResult<List<ProductDto>>> SearchProducts([FromQuery] string name)
{
    if (string.IsNullOrWhiteSpace(name))
        return BadRequest("Search term is required");

    // EF Core handles parameterization automatically
    var products = await _context.Products
        .Where(p => p.Name.Contains(name))
        .Select(p => new ProductDto { Id = p.Id, Name = p.Name, Price = p.Price })
        .Take(100)
        .ToListAsync();

    return Ok(products);
}

// If raw SQL is needed, use parameters
[HttpGet("products/raw-search")]
public async Task<ActionResult<List<Product>>> RawSearchProducts([FromQuery] string name)
{
    var products = await _context.Products
        .FromSqlInterpolated($"SELECT * FROM Products WHERE Name LIKE {'%' + name + '%'}")
        .ToListAsync();
    // Or use FromSqlRaw with explicit parameters
    // .FromSqlRaw("SELECT * FROM Products WHERE Name LIKE {0}", $"%{name}%")

    return Ok(products);
}

// Secure: Validate and sanitize input
[HttpGet("reports/{type}")]
public async Task<IActionResult> GetReport(string type)
{
    // Whitelist validation
    var allowedTypes = new[] { "sales", "inventory", "customers" };
    
    if (!allowedTypes.Contains(type.ToLower()))
        return BadRequest("Invalid report type");

    var report = await _reportService.GenerateAsync(type);
    return Ok(report);
}

// Secure: No command execution from user input
[HttpPost("export")]
public async Task<IActionResult> ExportData([FromBody] ExportRequest request)
{
    // Validate export format against whitelist
    if (!Enum.TryParse<ExportFormat>(request.Format, out var format))
        return BadRequest("Invalid format");

    // Use service method, not shell commands
    var data = await _exportService.ExportAsync(format);
    return File(data, GetContentType(format), $"export.{format.ToString().ToLower()}");
}
```

**Why**:
- SQL injection can dump or destroy your database
- Command injection gives attackers shell access
- Parameterized queries prevent injection
- Input validation adds defense in depth

---

### Rule 6: Implement Security Headers

**Priority**: High

**Description**: Configure security headers to protect against common web vulnerabilities.

**Incorrect**:

```csharp
// No security headers configured
var app = builder.Build();
app.MapControllers();
app.Run();
// Missing CORS, CSP, HSTS, etc.
```

**Correct**:

```csharp
// Program.cs - Configure security headers
builder.Services.AddCors(options =>
{
    options.AddPolicy("Production", policy =>
    {
        policy.WithOrigins("https://yourdomain.com", "https://app.yourdomain.com")
            .WithMethods("GET", "POST", "PUT", "DELETE")
            .WithHeaders("Authorization", "Content-Type")
            .SetPreflightMaxAge(TimeSpan.FromMinutes(10));
    });
});

var app = builder.Build();

// Security headers middleware
app.Use(async (context, next) =>
{
    // Prevent clickjacking
    context.Response.Headers.XFrameOptions = "DENY";
    
    // Prevent MIME type sniffing
    context.Response.Headers.XContentTypeOptions = "nosniff";
    
    // XSS protection
    context.Response.Headers["X-XSS-Protection"] = "1; mode=block";
    
    // Referrer policy
    context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    
    // Content Security Policy for APIs
    context.Response.Headers.ContentSecurityPolicy = "default-src 'none'; frame-ancestors 'none'";
    
    // Permissions policy
    context.Response.Headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()";

    await next();
});

// HTTPS redirection and HSTS
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}
app.UseHttpsRedirection();

// CORS - must be before Auth
app.UseCors("Production");

app.UseAuthentication();
app.UseAuthorization();

// Or use a dedicated package
// Install-Package NWebsec.AspNetCore.Middleware
app.UseXContentTypeOptions();
app.UseXXssProtection(options => options.EnabledWithBlockMode());
app.UseXfo(options => options.Deny());
app.UseReferrerPolicy(options => options.StrictOriginWhenCrossOrigin());
app.UseCsp(options => options
    .DefaultSources(s => s.None())
    .FrameAncestors(s => s.None()));
```

**Why**:
- Security headers prevent common attacks
- CORS controls which domains can access your API
- CSP prevents XSS and data injection
- HSTS enforces HTTPS

---

## Integration Example

Complete security configuration:

```csharp
// Program.cs - Security-focused configuration
var builder = WebApplication.CreateBuilder(args);

// Authentication
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(/* configuration */);

// Authorization with policies
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
        
    options.AddPolicy("OwnerOnly", policy =>
        policy.AddRequirements(new OwnerRequirement()));
});

builder.Services.AddScoped<IAuthorizationHandler, OwnerAuthorizationHandler>();

// Rate limiting
builder.Services.AddRateLimiter(/* configuration */);

// CORS
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.WithOrigins(builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()!)
            .WithMethods("GET", "POST", "PUT", "DELETE")
            .WithHeaders("Authorization", "Content-Type");
    });
});

var app = builder.Build();

// Security headers
app.Use(async (context, next) =>
{
    context.Response.Headers.XFrameOptions = "DENY";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers["X-XSS-Protection"] = "1; mode=block";
    context.Response.Headers.ContentSecurityPolicy = "default-src 'none'";
    await next();
});

app.UseHttpsRedirection();
app.UseHsts();
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] Object-level authorization on all data access
- [ ] DTOs used for all request/response (no mass assignment)
- [ ] Only necessary data returned (no excessive exposure)
- [ ] Rate limiting on authentication and expensive endpoints
- [ ] Parameterized queries (no SQL injection)
- [ ] Input validation and sanitization
- [ ] Security headers configured (CORS, CSP, HSTS, etc.)
- [ ] HTTPS enforced in production
- [ ] Audit logging for security events
- [ ] Error messages don't leak sensitive info

## References

- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [ASP.NET Core Security](https://docs.microsoft.com/aspnet/core/security/)
- [Rate Limiting in .NET 7+](https://docs.microsoft.com/aspnet/core/performance/rate-limit)
- [OWASP Cheat Sheets](https://cheatsheetseries.owasp.org/)

## Changelog

### v1.0.0
- Initial release
- 6 core rules based on OWASP API Top 10
