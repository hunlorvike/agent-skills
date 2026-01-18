---
name: secure-headers
description: Best practices for configuring security headers in ASP.NET Core including CORS, CSP, HSTS, and other HTTP security headers to protect against common web vulnerabilities.
version: 1.0.0
priority: high
categories:
  - security
  - headers
  - cors
use_when:
  - "When configuring API security"
  - "When setting up CORS"
  - "When preventing XSS and clickjacking"
  - "When preparing for security audits"
prerequisites:
  - "ASP.NET Core 8.0+"
related_skills:
  - owasp-api-security
  - jwt-authentication
---

# Secure Headers Best Practices

## Overview

This skill covers configuring security headers in ASP.NET Core to protect against common web vulnerabilities like XSS, clickjacking, and MIME type sniffing.

## Rules

### Rule 1: Configure CORS Properly

**Priority**: High

**Description**: Configure CORS with specific origins, methods, and headers. Never use wildcard in production.

**Incorrect**:

```csharp
// Dangerous: Allow all origins
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
            .AllowAnyMethod()
            .AllowAnyHeader();
    });
});

// Or no CORS configuration at all
```

**Correct**:

```csharp
// Production CORS configuration
builder.Services.AddCors(options =>
{
    options.AddPolicy("Production", policy =>
    {
        policy.WithOrigins(
                "https://app.example.com",
                "https://admin.example.com")
            .WithMethods("GET", "POST", "PUT", "DELETE", "PATCH")
            .WithHeaders("Authorization", "Content-Type", "X-Requested-With")
            .AllowCredentials() // Required when using cookies/auth
            .SetPreflightMaxAge(TimeSpan.FromMinutes(10));
    });

    // Development policy
    options.AddPolicy("Development", policy =>
    {
        policy.WithOrigins("http://localhost:3000", "http://localhost:5173")
            .AllowAnyMethod()
            .AllowAnyHeader()
            .AllowCredentials();
    });
});

var app = builder.Build();

// Apply CORS based on environment
if (app.Environment.IsDevelopment())
{
    app.UseCors("Development");
}
else
{
    app.UseCors("Production");
}

// CORS must be before UseAuthentication
app.UseCors("Production");
app.UseAuthentication();
app.UseAuthorization();
```

**Why**:
- Prevents unauthorized cross-origin requests
- Protects against CSRF attacks
- Allows legitimate cross-origin access
- Essential for SPA applications

---

### Rule 2: Set Security Headers

**Priority**: High

**Description**: Configure security headers to prevent XSS, clickjacking, and other attacks.

**Incorrect**:

```csharp
// No security headers
var app = builder.Build();
app.UseHttpsRedirection();
app.MapControllers();
app.Run();
```

**Correct**:

```csharp
// Security headers middleware
app.Use(async (context, next) =>
{
    // Prevent clickjacking
    context.Response.Headers.XFrameOptions = "DENY";
    
    // Prevent MIME type sniffing
    context.Response.Headers.XContentTypeOptions = "nosniff";
    
    // XSS protection (legacy but still useful)
    context.Response.Headers["X-XSS-Protection"] = "1; mode=block";
    
    // Referrer policy
    context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    
    // Content Security Policy for APIs
    context.Response.Headers["Content-Security-Policy"] = 
        "default-src 'none'; frame-ancestors 'none';";
    
    // Permissions Policy
    context.Response.Headers["Permissions-Policy"] = 
        "geolocation=(), microphone=(), camera=(), payment=()";
    
    // Strict Transport Security (HTTPS only)
    if (!app.Environment.IsDevelopment())
    {
        context.Response.Headers["Strict-Transport-Security"] = 
            "max-age=31536000; includeSubDomains; preload";
    }

    await next();
});

// Or use dedicated package
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
- Prevents XSS attacks
- Blocks clickjacking
- Prevents MIME sniffing
- Industry best practices

---

### Rule 3: Configure HSTS for HTTPS

**Priority**: High

**Description**: Enable HSTS to force HTTPS connections.

**Correct**:

```csharp
var app = builder.Build();

// HTTPS redirection
app.UseHttpsRedirection();

// HSTS - only in production
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

// Or configure HSTS options
builder.Services.AddHsts(options =>
{
    options.Preload = true;
    options.IncludeSubDomains = true;
    options.MaxAge = TimeSpan.FromDays(365);
});
```

**Why**:
- Forces HTTPS connections
- Prevents downgrade attacks
- Better security for production
- Required for many compliance standards

---

## Integration Example

Complete security headers setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("Production", policy =>
    {
        policy.WithOrigins(builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()!)
            .WithMethods("GET", "POST", "PUT", "DELETE")
            .WithHeaders("Authorization", "Content-Type")
            .AllowCredentials();
    });
});

// HSTS
if (!builder.Environment.IsDevelopment())
{
    builder.Services.AddHsts(options =>
    {
        options.Preload = true;
        options.IncludeSubDomains = true;
        options.MaxAge = TimeSpan.FromDays(365);
    });
}

var app = builder.Build();

// Security headers
app.Use(async (context, next) =>
{
    context.Response.Headers.XFrameOptions = "DENY";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers["X-XSS-Protection"] = "1; mode=block";
    context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    context.Response.Headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none';";
    await next();
});

app.UseHttpsRedirection();
if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseCors("Production");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] CORS configured with specific origins
- [ ] X-Frame-Options set to DENY
- [ ] X-Content-Type-Options set to nosniff
- [ ] Content-Security-Policy configured
- [ ] HSTS enabled in production
- [ ] Referrer-Policy configured
- [ ] Permissions-Policy set

## References

- [CORS in ASP.NET Core](https://docs.microsoft.com/aspnet/core/security/cors)
- [Security Headers](https://owasp.org/www-project-secure-headers/)

## Changelog

### v1.0.0
- Initial release
- 3 core rules for secure headers
