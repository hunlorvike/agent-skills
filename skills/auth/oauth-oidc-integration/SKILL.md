---
name: oauth-oidc-integration
description: Best practices for integrating OAuth 2.0 and OpenID Connect in ASP.NET Core applications for authentication with external identity providers.
version: 1.0.0
priority: critical
categories:
  - auth
  - oauth
  - oidc
use_when:
  - "When integrating with external identity providers"
  - "When implementing OAuth 2.0 flows"
  - "When using OpenID Connect"
  - "When supporting social login"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.AspNetCore.Authentication.OpenIdConnect"
related_skills:
  - jwt-authentication
  - policy-based-authorization
---

# OAuth 2.0 / OpenID Connect Integration

## Overview

This skill covers integrating OAuth 2.0 and OpenID Connect (OIDC) in ASP.NET Core for authentication with external identity providers like Azure AD, Google, GitHub, etc.

## Rules

### Rule 1: Configure OIDC Authentication Properly

**Priority**: Critical

**Description**: Properly configure OpenID Connect authentication with correct scopes and claims mapping.

**Incorrect**:

```csharp
// Incomplete configuration
builder.Services.AddAuthentication()
    .AddOpenIdConnect("oidc", options =>
    {
        options.Authority = "https://login.microsoftonline.com/tenant-id";
        options.ClientId = "client-id";
        // Missing ClientSecret, CallbackPath, etc.
    });
```

**Correct**:

```csharp
// Complete OIDC configuration
builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = CookieAuthenticationDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = OpenIdConnectDefaults.AuthenticationScheme;
})
.AddCookie()
.AddOpenIdConnect(options =>
{
    options.Authority = builder.Configuration["Oidc:Authority"];
    options.ClientId = builder.Configuration["Oidc:ClientId"];
    options.ClientSecret = builder.Configuration["Oidc:ClientSecret"];
    
    options.ResponseType = "code";
    options.CallbackPath = "/signin-oidc";
    options.SignedOutCallbackPath = "/signout-callback-oidc";
    
    // Scopes
    options.Scope.Add("openid");
    options.Scope.Add("profile");
    options.Scope.Add("email");
    options.Scope.Add("api://your-api/access_as_user");
    
    // Save tokens
    options.SaveTokens = true;
    
    // Claims mapping
    options.TokenValidationParameters = new TokenValidationParameters
    {
        NameClaimType = "name",
        RoleClaimType = "role"
    };
    
    // Events
    options.Events = new OpenIdConnectEvents
    {
        OnTokenValidated = context =>
        {
            // Add custom claims
            var claims = new List<Claim>
            {
                new("permission", "read"),
                new("permission", "write")
            };
            context.Principal?.AddIdentity(new ClaimsIdentity(claims));
            return Task.CompletedTask;
        },
        OnAuthenticationFailed = context =>
        {
            context.HandleResponse();
            context.Response.Redirect("/error");
            return Task.CompletedTask;
        }
    };
});
```

**Why**:
- Secure authentication flow
- Proper token handling
- Correct claims mapping
- Essential for production

---

### Rule 2: Use Secure Token Storage

**Priority**: Critical

**Description**: Store tokens securely, never in URL or client-side storage.

**Incorrect**:

```csharp
// Tokens in URL - security risk
options.CallbackPath = "/signin-oidc?token=..."; // Never do this

// Storing tokens in localStorage
localStorage.setItem('access_token', token); // XSS risk
```

**Correct**:

```csharp
// Tokens stored in secure cookies
builder.Services.AddAuthentication()
    .AddCookie(options =>
    {
        options.Cookie.Name = "AuthCookie";
        options.Cookie.HttpOnly = true;
        options.Cookie.Secure = true; // HTTPS only
        options.Cookie.SameSite = SameSiteMode.Lax;
    })
    .AddOpenIdConnect(options =>
    {
        options.SaveTokens = true; // Saved in authentication cookie
        // Tokens accessible via HttpContext.GetTokenAsync()
    });

// Access tokens in API
[HttpGet("protected")]
public async Task<IActionResult> GetProtectedData()
{
    var accessToken = await HttpContext.GetTokenAsync("access_token");
    // Use token for API calls
}
```

**Why**:
- Prevents token theft
- HttpOnly cookies prevent XSS access
- Secure storage
- Industry best practice

---

### Rule 3: Handle Token Refresh

**Priority**: High

**Description**: Implement automatic token refresh for long-lived sessions.

**Correct**:

```csharp
builder.Services.AddAuthentication()
    .AddOpenIdConnect(options =>
    {
        // ... configuration ...
        
        options.Events = new OpenIdConnectEvents
        {
            OnTokenValidated = async context =>
            {
                // Store refresh token
                var refreshToken = context.TokenEndpointResponse?.RefreshToken;
                if (!string.IsNullOrEmpty(refreshToken))
                {
                    // Store in database or secure storage
                    await StoreRefreshTokenAsync(context.Principal, refreshToken);
                }
            }
        };
    });

// Token refresh middleware
public class TokenRefreshMiddleware
{
    private readonly RequestDelegate _next;
    private readonly IConfiguration _configuration;

    public TokenRefreshMiddleware(RequestDelegate next, IConfiguration configuration)
    {
        _next = next;
        _configuration = configuration;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (context.User?.Identity?.IsAuthenticated == true)
        {
            var expiresAt = context.User.FindFirst("exp")?.Value;
            if (!string.IsNullOrEmpty(expiresAt) && 
                DateTimeOffset.FromUnixTimeSeconds(long.Parse(expiresAt)) < DateTimeOffset.UtcNow.AddMinutes(5))
            {
                // Token expiring soon, refresh it
                await RefreshTokenAsync(context);
            }
        }

        await _next(context);
    }

    private async Task RefreshTokenAsync(HttpContext context)
    {
        // Implement token refresh logic
    }
}
```

**Why**:
- Maintains user sessions
- Prevents frequent re-authentication
- Better user experience
- Secure token management

---

## Integration Example

Complete OIDC setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = CookieAuthenticationDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = OpenIdConnectDefaults.AuthenticationScheme;
})
.AddCookie()
.AddOpenIdConnect(options =>
{
    var oidc = builder.Configuration.GetSection("Oidc");
    options.Authority = oidc["Authority"];
    options.ClientId = oidc["ClientId"];
    options.ClientSecret = oidc["ClientSecret"];
    options.ResponseType = "code";
    options.CallbackPath = "/signin-oidc";
    options.SaveTokens = true;
    options.Scope.Add("openid");
    options.Scope.Add("profile");
    options.Scope.Add("email");
});

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] OIDC properly configured
- [ ] Secure token storage
- [ ] Token refresh implemented
- [ ] Claims mapping correct
- [ ] Error handling configured
- [ ] Scopes properly requested
- [ ] Callback paths secured

## References

- [OpenID Connect](https://docs.microsoft.com/aspnet/core/security/authentication/openid-connect)
- [OAuth 2.0](https://oauth.net/2/)

## Changelog

### v1.0.0
- Initial release
- 3 core rules for OAuth/OIDC integration
