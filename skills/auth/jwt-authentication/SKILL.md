---
name: jwt-authentication
description: Best practices for implementing JWT Bearer token authentication in ASP.NET Core, including token generation, validation, refresh tokens, and security considerations.
version: 1.0.0
priority: critical
categories:
  - auth
  - security
  - api
use_when:
  - "When implementing API authentication"
  - "When configuring JWT in ASP.NET Core"
  - "When reviewing authentication code"
  - "When securing API endpoints"
  - "When implementing token refresh"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.AspNetCore.Authentication.JwtBearer"
related_skills:
  - oauth-oidc-integration
  - policy-based-authorization
  - owasp-api-security
---

# JWT Authentication Best Practices

## Overview

This skill covers secure implementation of JWT (JSON Web Token) authentication in ASP.NET Core APIs. Proper JWT implementation is critical for API security. This skill addresses:

- Token generation and validation
- Secure key management
- Refresh token implementation
- Common security pitfalls

## Rules

### Rule 1: Use Strong Signing Keys and Algorithms

**Priority**: Critical

**Description**: Use strong cryptographic keys (256+ bits) and secure algorithms (RS256 or HS256). Never use weak or predictable keys.

**Incorrect**:

```csharp
// Weak key - too short and predictable
var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("secret"));

// Hardcoded key in code
var key = new SymmetricSecurityKey(
    Encoding.UTF8.GetBytes("my-super-secret-key-12345"));

// Using none algorithm
var credentials = new SigningCredentials(key, SecurityAlgorithms.None);

// Configuration with weak key
{
  "Jwt": {
    "Key": "short" // Only 5 characters!
  }
}
```

**Correct**:

```csharp
// appsettings.json (key should be in secrets/vault in production)
{
  "Jwt": {
    "Key": "your-256-bit-secret-key-here-at-least-32-characters-long!",
    "Issuer": "https://yourdomain.com",
    "Audience": "https://yourdomain.com",
    "ExpiryMinutes": 60
  }
}

// Program.cs - Load from configuration
var jwtSettings = builder.Configuration.GetSection("Jwt");
var key = new SymmetricSecurityKey(
    Encoding.UTF8.GetBytes(jwtSettings["Key"]!));

// For production - use RSA keys
public class JwtSettings
{
    public string PrivateKeyPath { get; set; } = string.Empty;
    public string PublicKeyPath { get; set; } = string.Empty;
    public string Issuer { get; set; } = string.Empty;
    public string Audience { get; set; } = string.Empty;
    public int ExpiryMinutes { get; set; } = 60;
}

// RSA key loading
var privateKey = RSA.Create();
privateKey.ImportRSAPrivateKey(
    File.ReadAllBytes(settings.PrivateKeyPath), out _);

var signingCredentials = new SigningCredentials(
    new RsaSecurityKey(privateKey),
    SecurityAlgorithms.RsaSha256);

// Or use Azure Key Vault / AWS KMS for key management
builder.Services.AddAzureKeyVault(/* ... */);
```

**Why**:
- Short keys can be brute-forced
- Hardcoded keys end up in source control
- RSA (asymmetric) allows public key distribution for validation
- Key management services provide rotation and audit

---

### Rule 2: Configure Token Validation Properly

**Priority**: Critical

**Description**: Always validate issuer, audience, lifetime, and signature. Don't disable any validation in production.

**Incorrect**:

```csharp
// Disabling critical validations
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = false,           // Dangerous!
            ValidateAudience = false,         // Dangerous!
            ValidateLifetime = false,         // Very dangerous!
            ValidateIssuerSigningKey = false, // Extremely dangerous!
            IssuerSigningKey = key
        };
    });

// Not setting clock skew
options.TokenValidationParameters = new TokenValidationParameters
{
    // Default ClockSkew is 5 minutes - might be too long
};
```

**Correct**:

```csharp
// Program.cs - Complete JWT configuration
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    var jwtSettings = builder.Configuration.GetSection("Jwt").Get<JwtSettings>()!;
    
    options.TokenValidationParameters = new TokenValidationParameters
    {
        // Validate the issuer (who created the token)
        ValidateIssuer = true,
        ValidIssuer = jwtSettings.Issuer,

        // Validate the audience (who the token is for)
        ValidateAudience = true,
        ValidAudience = jwtSettings.Audience,

        // Validate token expiry
        ValidateLifetime = true,

        // Validate the signing key
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(jwtSettings.Key)),

        // Reduce clock skew (default is 5 minutes)
        ClockSkew = TimeSpan.FromMinutes(1),

        // Ensure token has an expiry
        RequireExpirationTime = true,

        // Ensure token is not used before valid
        RequireSignedTokens = true
    };

    // Handle authentication events
    options.Events = new JwtBearerEvents
    {
        OnAuthenticationFailed = context =>
        {
            if (context.Exception is SecurityTokenExpiredException)
            {
                context.Response.Headers.Append("Token-Expired", "true");
            }
            return Task.CompletedTask;
        },
        OnTokenValidated = context =>
        {
            // Additional validation if needed
            var userId = context.Principal?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            // Could check if user still exists, is not locked, etc.
            return Task.CompletedTask;
        }
    };
});

// Don't forget UseAuthentication and UseAuthorization in correct order!
app.UseAuthentication();
app.UseAuthorization();
```

**Why**:
- Disabled validation allows forged tokens
- Issuer validation prevents tokens from other systems
- Audience validation ensures token is meant for your API
- Lifetime validation prevents expired tokens

---

### Rule 3: Generate Tokens Securely

**Priority**: Critical

**Description**: Include appropriate claims, set reasonable expiry, and never include sensitive data in tokens.

**Incorrect**:

```csharp
// Bad token generation
public string GenerateToken(User user)
{
    var claims = new[]
    {
        new Claim("password", user.Password), // NEVER include password!
        new Claim("ssn", user.SSN),           // No sensitive PII!
        new Claim("creditCard", user.CardNumber), // Absolutely not!
    };

    var token = new JwtSecurityToken(
        claims: claims,
        expires: DateTime.Now.AddYears(1), // Way too long!
        signingCredentials: credentials
    );

    return new JwtSecurityTokenHandler().WriteToken(token);
}
```

**Correct**:

```csharp
public interface ITokenService
{
    string GenerateAccessToken(User user);
    RefreshToken GenerateRefreshToken();
}

public class TokenService : ITokenService
{
    private readonly JwtSettings _settings;
    private readonly ILogger<TokenService> _logger;

    public TokenService(IOptions<JwtSettings> settings, ILogger<TokenService> logger)
    {
        _settings = settings.Value;
        _logger = logger;
    }

    public string GenerateAccessToken(User user)
    {
        var claims = new List<Claim>
        {
            // Standard claims
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Email, user.Email),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()), // Unique token ID
            new(JwtRegisteredClaimNames.Iat, DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(), 
                ClaimValueTypes.Integer64),
            
            // Custom claims - only non-sensitive data
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.UserName),
        };

        // Add roles as claims
        foreach (var role in user.Roles)
        {
            claims.Add(new Claim(ClaimTypes.Role, role));
        }

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_settings.Key));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: _settings.Issuer,
            audience: _settings.Audience,
            claims: claims,
            notBefore: DateTime.UtcNow,
            expires: DateTime.UtcNow.AddMinutes(_settings.ExpiryMinutes),
            signingCredentials: credentials
        );

        _logger.LogInformation(
            "Generated access token for user {UserId}, expires at {Expiry}",
            user.Id, token.ValidTo);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public RefreshToken GenerateRefreshToken()
    {
        var randomBytes = new byte[64];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(randomBytes);

        return new RefreshToken
        {
            Token = Convert.ToBase64String(randomBytes),
            ExpiresAt = DateTime.UtcNow.AddDays(7),
            CreatedAt = DateTime.UtcNow
        };
    }
}

// Refresh token entity
public class RefreshToken
{
    public int Id { get; set; }
    public string Token { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public string? ReplacedByToken { get; set; }
    public int UserId { get; set; }
    
    public bool IsExpired => DateTime.UtcNow >= ExpiresAt;
    public bool IsRevoked => RevokedAt != null;
    public bool IsActive => !IsRevoked && !IsExpired;
}
```

**Why**:
- Tokens are Base64 encoded, not encrypted - anyone can read claims
- Short expiry limits damage from compromised tokens
- JTI (JWT ID) enables token revocation
- Refresh tokens allow secure token renewal

---

### Rule 4: Implement Token Refresh Properly

**Priority**: High

**Description**: Use refresh tokens to issue new access tokens without re-authentication. Implement refresh token rotation.

**Incorrect**:

```csharp
// No refresh token - forcing re-login on expiry
[HttpPost("login")]
public async Task<IActionResult> Login(LoginRequest request)
{
    var user = await _authService.ValidateAsync(request);
    var token = _tokenService.GenerateAccessToken(user);
    return Ok(new { token }); // No refresh token!
}

// Refresh without rotation
[HttpPost("refresh")]
public async Task<IActionResult> Refresh(string refreshToken)
{
    var user = await GetUserByRefreshToken(refreshToken);
    var newAccessToken = _tokenService.GenerateAccessToken(user);
    return Ok(new { accessToken = newAccessToken }); // Same refresh token reused!
}
```

**Correct**:

```csharp
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;
    private readonly ITokenService _tokenService;
    private readonly IRefreshTokenRepository _refreshTokenRepo;

    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login(LoginRequest request)
    {
        var user = await _authService.ValidateCredentialsAsync(
            request.Email, request.Password);

        if (user is null)
            return Unauthorized(new { message = "Invalid credentials" });

        var accessToken = _tokenService.GenerateAccessToken(user);
        var refreshToken = _tokenService.GenerateRefreshToken();

        // Store refresh token in database
        user.RefreshTokens.Add(refreshToken);
        await _authService.UpdateUserAsync(user);

        // Set refresh token in HTTP-only cookie
        SetRefreshTokenCookie(refreshToken.Token);

        return Ok(new AuthResponse
        {
            AccessToken = accessToken,
            ExpiresAt = DateTime.UtcNow.AddMinutes(_settings.ExpiryMinutes)
        });
    }

    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> RefreshToken()
    {
        var refreshToken = Request.Cookies["refreshToken"];
        
        if (string.IsNullOrEmpty(refreshToken))
            return Unauthorized(new { message = "Refresh token is required" });

        var user = await _authService.GetUserByRefreshTokenAsync(refreshToken);

        if (user is null)
            return Unauthorized(new { message = "Invalid refresh token" });

        var existingToken = user.RefreshTokens
            .SingleOrDefault(t => t.Token == refreshToken);

        if (existingToken is null || !existingToken.IsActive)
        {
            // Possible token reuse attack - revoke all tokens
            if (existingToken?.IsRevoked == true)
            {
                await RevokeAllUserTokensAsync(user);
                return Unauthorized(new { message = "Token reuse detected" });
            }
            return Unauthorized(new { message = "Invalid refresh token" });
        }

        // Rotate refresh token
        var newRefreshToken = _tokenService.GenerateRefreshToken();
        
        existingToken.RevokedAt = DateTime.UtcNow;
        existingToken.ReplacedByToken = newRefreshToken.Token;
        
        user.RefreshTokens.Add(newRefreshToken);
        await _authService.UpdateUserAsync(user);

        var newAccessToken = _tokenService.GenerateAccessToken(user);
        SetRefreshTokenCookie(newRefreshToken.Token);

        return Ok(new AuthResponse
        {
            AccessToken = newAccessToken,
            ExpiresAt = DateTime.UtcNow.AddMinutes(_settings.ExpiryMinutes)
        });
    }

    [Authorize]
    [HttpPost("revoke")]
    public async Task<IActionResult> RevokeToken()
    {
        var refreshToken = Request.Cookies["refreshToken"];
        
        if (string.IsNullOrEmpty(refreshToken))
            return BadRequest(new { message = "Token is required" });

        var result = await _authService.RevokeTokenAsync(refreshToken);

        if (!result)
            return NotFound(new { message = "Token not found" });

        // Clear the cookie
        Response.Cookies.Delete("refreshToken");

        return Ok(new { message = "Token revoked" });
    }

    private void SetRefreshTokenCookie(string token)
    {
        var cookieOptions = new CookieOptions
        {
            HttpOnly = true,
            Secure = true, // HTTPS only
            SameSite = SameSiteMode.Strict,
            Expires = DateTime.UtcNow.AddDays(7)
        };

        Response.Cookies.Append("refreshToken", token, cookieOptions);
    }
}

public record AuthResponse
{
    public string AccessToken { get; init; } = string.Empty;
    public DateTime ExpiresAt { get; init; }
}
```

**Why**:
- Refresh tokens allow longer sessions without long-lived access tokens
- Token rotation prevents refresh token theft
- HTTP-only cookies prevent XSS access to refresh tokens
- Revoking all tokens on reuse detects theft

---

### Rule 5: Handle Token Storage Securely (Client-Side)

**Priority**: High

**Description**: Store tokens securely on the client. Access tokens in memory, refresh tokens in HTTP-only cookies.

**Incorrect**:

```javascript
// BAD: Storing JWT in localStorage
localStorage.setItem('token', response.accessToken);

// BAD: Storing in sessionStorage (still accessible to XSS)
sessionStorage.setItem('token', response.accessToken);

// BAD: Storing refresh token in JavaScript accessible location
localStorage.setItem('refreshToken', response.refreshToken);
```

**Correct**:

```csharp
// Server-side: Return access token in response body, 
// set refresh token in HTTP-only cookie (see Rule 4)

[HttpPost("login")]
public async Task<ActionResult<AuthResponse>> Login(LoginRequest request)
{
    // ... validation ...

    var accessToken = _tokenService.GenerateAccessToken(user);
    var refreshToken = _tokenService.GenerateRefreshToken();

    // Refresh token in HTTP-only secure cookie
    Response.Cookies.Append("refreshToken", refreshToken.Token, new CookieOptions
    {
        HttpOnly = true,          // Not accessible via JavaScript
        Secure = true,            // HTTPS only
        SameSite = SameSiteMode.Strict, // CSRF protection
        Expires = DateTime.UtcNow.AddDays(7),
        Path = "/api/auth"        // Only sent to auth endpoints
    });

    // Access token in response body - stored in memory by client
    return Ok(new AuthResponse
    {
        AccessToken = accessToken,
        ExpiresAt = DateTime.UtcNow.AddMinutes(15)
    });
}
```

```javascript
// Client-side (JavaScript/React example)
class AuthService {
    private accessToken: string | null = null;

    async login(email: string, password: string): Promise<void> {
        const response = await fetch('/api/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            credentials: 'include', // Important for cookies
            body: JSON.stringify({ email, password })
        });

        const data = await response.json();
        // Store in memory only - not localStorage
        this.accessToken = data.accessToken;
    }

    async refreshToken(): Promise<void> {
        // Cookie sent automatically with credentials: 'include'
        const response = await fetch('/api/auth/refresh', {
            method: 'POST',
            credentials: 'include'
        });

        const data = await response.json();
        this.accessToken = data.accessToken;
    }

    getAccessToken(): string | null {
        return this.accessToken;
    }
}
```

**Why**:
- localStorage/sessionStorage accessible to XSS attacks
- HTTP-only cookies not accessible via JavaScript
- Memory storage cleared on page refresh (use refresh token to restore)
- SameSite prevents CSRF attacks

---

### Rule 6: Secure Endpoints with Authorization

**Priority**: High

**Description**: Always require authentication on protected endpoints. Use policy-based authorization for fine-grained access control.

**Incorrect**:

```csharp
// Forgetting [Authorize] attribute
[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetOrders() // No auth required!
    {
        return Ok(await _service.GetAllOrdersAsync());
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteOrder(int id) // Anyone can delete!
    {
        await _service.DeleteAsync(id);
        return NoContent();
    }
}
```

**Correct**:

```csharp
// Program.cs - Configure authorization policies
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("RequireAdmin", policy =>
        policy.RequireRole("Admin"));

    options.AddPolicy("RequireManager", policy =>
        policy.RequireRole("Admin", "Manager"));

    options.AddPolicy("CanManageOrders", policy =>
        policy.RequireAssertion(context =>
            context.User.HasClaim(c => c.Type == "Permission" && c.Value == "orders.manage") ||
            context.User.IsInRole("Admin")));

    // Require authentication by default for all endpoints
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});

// Controller with proper authorization
[ApiController]
[Route("api/[controller]")]
[Authorize] // Require authentication for all actions
public class OrdersController : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IEnumerable<OrderDto>>> GetOrders()
    {
        // Get only user's orders
        var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var orders = await _service.GetOrdersByUserAsync(userId);
        return Ok(orders);
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<OrderDto>> GetOrder(int id)
    {
        var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var order = await _service.GetOrderAsync(id);

        // Verify ownership
        if (order.UserId != userId && !User.IsInRole("Admin"))
            return Forbid();

        return Ok(order);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = "RequireAdmin")] // Only admins can delete
    public async Task<IActionResult> DeleteOrder(int id)
    {
        await _service.DeleteAsync(id);
        return NoContent();
    }

    [HttpPost("{id}/approve")]
    [Authorize(Policy = "CanManageOrders")]
    public async Task<IActionResult> ApproveOrder(int id)
    {
        await _service.ApproveAsync(id);
        return Ok();
    }

    [AllowAnonymous] // Override for public endpoints
    [HttpGet("public/featured")]
    public async Task<ActionResult<IEnumerable<OrderDto>>> GetFeaturedOrders()
    {
        return Ok(await _service.GetFeaturedAsync());
    }
}
```

**Why**:
- Missing auth exposes sensitive data
- Role-based access provides basic protection
- Policy-based authorization enables complex rules
- FallbackPolicy ensures no endpoint is accidentally unprotected

---

## Integration Example

Complete authentication setup:

```csharp
// Program.cs
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// Configure JWT settings
builder.Services.Configure<JwtSettings>(
    builder.Configuration.GetSection("Jwt"));

var jwtSettings = builder.Configuration.GetSection("Jwt").Get<JwtSettings>()!;

// Add Authentication
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidIssuer = jwtSettings.Issuer,
        ValidateAudience = true,
        ValidAudience = jwtSettings.Audience,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(jwtSettings.Key)),
        ClockSkew = TimeSpan.FromMinutes(1)
    };

    options.Events = new JwtBearerEvents
    {
        OnAuthenticationFailed = context =>
        {
            var logger = context.HttpContext.RequestServices
                .GetRequiredService<ILogger<Program>>();
            logger.LogWarning("Authentication failed: {Message}", 
                context.Exception.Message);
            return Task.CompletedTask;
        }
    };
});

// Add Authorization
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});

// Register services
builder.Services.AddScoped<ITokenService, TokenService>();
builder.Services.AddScoped<IAuthService, AuthService>();

var app = builder.Build();

// Order matters!
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
```

## Checklist

- [ ] Using strong signing keys (256+ bits)
- [ ] Keys stored securely (not in code)
- [ ] All token validation enabled (issuer, audience, lifetime, signature)
- [ ] Reasonable token expiry (15-60 minutes for access tokens)
- [ ] Refresh tokens implemented with rotation
- [ ] Refresh tokens in HTTP-only secure cookies
- [ ] No sensitive data in token claims
- [ ] Authorization on all protected endpoints
- [ ] Fallback policy requires authentication
- [ ] Token expiry header for client handling

## References

- [JWT Bearer Authentication](https://docs.microsoft.com/aspnet/core/security/authentication/jwt)
- [RFC 7519 - JWT](https://datatracker.ietf.org/doc/html/rfc7519)
- [OWASP JWT Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/JSON_Web_Token_for_Java_Cheat_Sheet.html)
- [Token Storage Best Practices](https://auth0.com/docs/secure/security-guidance/data-security/token-storage)

## Changelog

### v1.0.0
- Initial release
- 6 core rules for JWT authentication
