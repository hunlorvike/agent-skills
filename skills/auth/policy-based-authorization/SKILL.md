---
name: policy-based-authorization
description: Best practices for implementing policy-based authorization in ASP.NET Core using requirements, handlers, and resource-based authorization.
version: 1.0.0
priority: high
categories:
  - auth
  - authorization
  - security
use_when:
  - "When implementing complex authorization rules"
  - "When role-based authorization is insufficient"
  - "When implementing resource-based authorization"
  - "When creating custom authorization policies"
prerequisites:
  - "ASP.NET Core 8.0+"
related_skills:
  - jwt-authentication
  - owasp-api-security
---

# Policy-Based Authorization Best Practices

## Overview

This skill covers policy-based authorization in ASP.NET Core. Policies provide flexible, reusable authorization rules beyond simple role checks.

## Rules

### Rule 1: Create Reusable Authorization Policies

**Priority**: High

**Description**: Define policies in Program.cs for reuse across controllers.

**Incorrect**:

```csharp
// Inline authorization - not reusable
[Authorize(Roles = "Admin,Manager")]
public class OrdersController : ControllerBase { }

// Duplicated logic
[Authorize(Roles = "Admin,Manager")]
public class ProductsController : ControllerBase { }
```

**Correct**:

```csharp
// Program.cs - Define policies
builder.Services.AddAuthorization(options =>
{
    // Simple policy
    options.AddPolicy("AdminOnly", policy =>
        policy.RequireRole("Admin"));

    // Policy with multiple requirements
    options.AddPolicy("ManagerOrAdmin", policy =>
        policy.RequireRole("Admin", "Manager"));

    // Policy with claims
    options.AddPolicy("CanEditProducts", policy =>
        policy.RequireClaim("Permission", "products.edit"));

    // Policy with multiple claims (AND)
    options.AddPolicy("CanManageOrders", policy =>
    {
        policy.RequireClaim("Permission", "orders.view");
        policy.RequireClaim("Permission", "orders.edit");
    });

    // Policy with assertion
    options.AddPolicy("Over18", policy =>
        policy.RequireAssertion(context =>
            context.User.HasClaim(c => c.Type == "Age" && 
                int.TryParse(c.Value, out var age) && age >= 18)));

    // Policy with authentication only
    options.AddPolicy("Authenticated", policy =>
        policy.RequireAuthenticatedUser());
});

// Use in controllers
[Authorize(Policy = "ManagerOrAdmin")]
public class OrdersController : ControllerBase { }

[Authorize(Policy = "CanEditProducts")]
public class ProductsController : ControllerBase { }
```

**Why**:
- Reusable across controllers
- Centralized policy definition
- Easier to maintain
- Clear policy names

---

### Rule 2: Implement Custom Authorization Requirements

**Priority**: High

**Description**: Create custom requirements and handlers for complex authorization logic.

**Incorrect**:

```csharp
// Complex logic in controller
[HttpDelete("orders/{id}")]
public async Task<IActionResult> DeleteOrder(int id)
{
    var order = await _context.Orders.FindAsync(id);
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    
    // Authorization logic mixed with business logic
    if (order.UserId.ToString() != userId && !User.IsInRole("Admin"))
        return Forbid();
    
    _context.Orders.Remove(order);
    await _context.SaveChangesAsync();
    return NoContent();
}
```

**Correct**:

```csharp
// Custom requirement
public class OwnerRequirement : IAuthorizationRequirement
{
}

// Authorization handler
public class OwnerAuthorizationHandler : AuthorizationHandler<OwnerRequirement, Order>
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

// Register handler
builder.Services.AddScoped<IAuthorizationHandler, OwnerAuthorizationHandler>();

// Define policy
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("OwnerOnly", policy =>
        policy.Requirements.Add(new OwnerRequirement()));
});

// Use in controller
[HttpDelete("orders/{id}")]
[Authorize(Policy = "OwnerOnly")]
public async Task<IActionResult> DeleteOrder(int id)
{
    var order = await _context.Orders.FindAsync(id);
    if (order == null)
        return NotFound();

    // Authorization handled by policy
    _context.Orders.Remove(order);
    await _context.SaveChangesAsync();
    return NoContent();
}

// Or use IAuthorizationService directly
[HttpDelete("orders/{id}")]
public async Task<IActionResult> DeleteOrder(int id, IAuthorizationService authService)
{
    var order = await _context.Orders.FindAsync(id);
    if (order == null)
        return NotFound();

    var authResult = await authService.AuthorizeAsync(User, order, "OwnerOnly");
    if (!authResult.Succeeded)
        return Forbid();

    _context.Orders.Remove(order);
    await _context.SaveChangesAsync();
    return NoContent();
}
```

**Why**:
- Separates authorization from business logic
- Testable authorization logic
- Reusable across endpoints
- Follows single responsibility

---

### Rule 3: Use Resource-Based Authorization

**Priority**: High

**Description**: Authorize access to specific resources, not just endpoints.

**Incorrect**:

```csharp
// Only endpoint-level authorization
[Authorize]
[HttpGet("orders/{id}")]
public async Task<ActionResult<Order>> GetOrder(int id)
{
    // Any authenticated user can access any order!
    return Ok(await _context.Orders.FindAsync(id));
}
```

**Correct**:

```csharp
// Resource-based authorization
public class OrderAuthorizationHandler : AuthorizationHandler<OwnerRequirement, Order>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        OwnerRequirement requirement,
        Order resource)
    {
        var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        
        // Check ownership
        if (resource.UserId.ToString() == userId)
        {
            context.Succeed(requirement);
        }
        // Or admin role
        else if (context.User.IsInRole("Admin"))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}

// Use IAuthorizationService
[Authorize]
[HttpGet("orders/{id}")]
public async Task<ActionResult<OrderDto>> GetOrder(
    int id,
    IAuthorizationService authService)
{
    var order = await _context.Orders.FindAsync(id);
    if (order == null)
        return NotFound();

    // Authorize access to this specific resource
    var authResult = await authService.AuthorizeAsync(User, order, "OwnerOnly");
    if (!authResult.Succeeded)
        return Forbid();

    return Ok(_mapper.Map<OrderDto>(order));
}
```

**Why**:
- Prevents unauthorized access to resources
- Essential for multi-tenant applications
- Enforces data isolation
- Prevents BOLA vulnerabilities

---

### Rule 4: Combine Multiple Authorization Policies

**Priority**: Medium

**Description**: Use multiple policies with AND/OR logic when needed.

**Correct**:

```csharp
// Multiple policies (AND - all must pass)
[Authorize(Policy = "CanViewOrders")]
[Authorize(Policy = "IsActiveUser")]
public class OrdersController : ControllerBase
{
    // Both policies must succeed
}

// OR logic using custom handler
public class ManagerOrOwnerRequirement : IAuthorizationRequirement
{
}

public class ManagerOrOwnerHandler : AuthorizationHandler<ManagerOrOwnerRequirement, Order>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context,
        ManagerOrOwnerRequirement requirement,
        Order resource)
    {
        var userId = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        
        // OR logic: Manager role OR owner
        if (context.User.IsInRole("Manager") || 
            resource.UserId.ToString() == userId)
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}

// Policy with multiple handlers (OR - any can succeed)
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("ManagerOrOwner", policy =>
    {
        policy.Requirements.Add(new ManagerOrOwnerRequirement());
    });
});

// Multiple handlers registered - any can succeed
builder.Services.AddScoped<IAuthorizationHandler, ManagerOrOwnerHandler>();
builder.Services.AddScoped<IAuthorizationHandler, AdminBypassHandler>();
```

**Why**:
- Flexible authorization rules
- Supports complex business requirements
- Reusable policy combinations
- Clear authorization logic

---

## Integration Example

Complete authorization setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(/* ... */);

builder.Services.AddAuthorization(options =>
{
    // Simple policies
    options.AddPolicy("AdminOnly", policy => policy.RequireRole("Admin"));
    options.AddPolicy("ManagerOrAdmin", policy => 
        policy.RequireRole("Admin", "Manager"));

    // Claim-based policies
    options.AddPolicy("CanEditProducts", policy =>
        policy.RequireClaim("Permission", "products.edit"));

    // Custom requirement policies
    options.AddPolicy("OwnerOnly", policy =>
        policy.Requirements.Add(new OwnerRequirement()));

    // Fallback policy
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();
});

// Register authorization handlers
builder.Services.AddScoped<IAuthorizationHandler, OwnerAuthorizationHandler>();
builder.Services.AddScoped<IAuthorizationHandler, ManagerOrOwnerHandler>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] Policies defined in Program.cs
- [ ] Custom requirements for complex logic
- [ ] Resource-based authorization implemented
- [ ] Authorization handlers registered
- [ ] Policies tested
- [ ] Fallback policy configured
- [ ] Authorization separated from business logic

## References

- [Policy-Based Authorization](https://docs.microsoft.com/aspnet/core/security/authorization/policies)
- [Resource-Based Authorization](https://docs.microsoft.com/aspnet/core/security/authorization/resourcebased)

## Changelog

### v1.0.0
- Initial release
- 4 core rules for policy-based authorization
