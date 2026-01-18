---
name: api-versioning
description: Best practices for implementing API versioning in ASP.NET Core using URL path, query string, or header-based versioning strategies.
version: 1.0.0
priority: high
categories:
  - api
  - versioning
use_when:
  - "When designing versioned APIs"
  - "When breaking changes are needed"
  - "When maintaining backward compatibility"
  - "When multiple API versions coexist"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.AspNetCore.Mvc.Versioning"
related_skills:
  - webapi-best-practices
  - openapi-swagger
---

# API Versioning Best Practices

## Overview

This skill covers strategies for versioning ASP.NET Core APIs. Proper versioning allows you to evolve your API while maintaining backward compatibility.

## Rules

### Rule 1: Choose the Right Versioning Strategy

**Priority**: High

**Description**: Select versioning strategy based on your requirements: URL path (recommended), query string, or header-based.

**Incorrect**:

```csharp
// No versioning - breaking changes affect all clients
[ApiController]
[Route("api/products")]
public class ProductsController : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<Product>>> GetProducts()
    {
        // Version 1 implementation
    }
}

// Later, breaking change breaks all clients
[HttpGet]
public async Task<ActionResult<List<ProductDto>>> GetProducts() // Changed return type!
{
    // Version 2 implementation
}
```

**Correct**:

```csharp
// URL Path Versioning (Recommended)
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("1.0")]
public class ProductsV1Controller : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<Product>>> GetProducts()
    {
        // Version 1 - returns Product entities
    }
}

[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("2.0")]
public class ProductsV2Controller : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<ProductDto>>> GetProducts()
    {
        // Version 2 - returns ProductDto
    }
}

// Program.cs configuration
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = ApiVersionReader.Combine(
        new UrlSegmentApiVersionReader(),
        new QueryStringApiVersionReader("version"),
        new HeaderApiVersionReader("X-Version")
    );
});

builder.Services.AddVersionedApiExplorer(options =>
{
    options.GroupNameFormat = "'v'VVV";
    options.SubstituteApiVersionInUrl = true;
});
```

**Why**:
- URL path versioning is most RESTful and discoverable
- Allows multiple versions to coexist
- Clients explicitly choose version
- Clear version in URL

---

### Rule 2: Use Semantic Versioning

**Priority**: High

**Description**: Follow semantic versioning (MAJOR.MINOR) where MAJOR indicates breaking changes.

**Incorrect**:

```csharp
// Arbitrary versioning
[ApiVersion("1")]
[ApiVersion("2")]
[ApiVersion("3.5.2")] // Confusing
[ApiVersion("2024-01-15")] // Date-based - not semantic
```

**Correct**:

```csharp
// Semantic versioning
[ApiVersion("1.0")] // Initial version
[ApiVersion("1.1")] // Minor changes, backward compatible
[ApiVersion("2.0")] // Breaking changes

// Program.cs
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ApiVersionReader = ApiVersionReader.Combine(
        new UrlSegmentApiVersionReader()
    );
});

// Controller with multiple versions
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("1.0")]
[ApiVersion("1.1")] // Both versions supported
public class ProductsController : ControllerBase
{
    [HttpGet]
    [MapToApiVersion("1.0")]
    public async Task<ActionResult<List<Product>>> GetProductsV1()
    {
        // Version 1.0 implementation
    }

    [HttpGet]
    [MapToApiVersion("1.1")]
    public async Task<ActionResult<List<ProductDto>>> GetProductsV1_1()
    {
        // Version 1.1 - added pagination
    }
}
```

**Why**:
- Semantic versioning is industry standard
- Clear meaning: MAJOR = breaking, MINOR = compatible
- Easier for clients to understand
- Tooling support

---

### Rule 3: Deprecate Old Versions Gracefully

**Priority**: Medium

**Description**: Mark deprecated versions and provide migration guidance.

**Incorrect**:

```csharp
// Removing version without notice
[ApiVersion("1.0")] // Suddenly removed - breaks clients
public class ProductsV1Controller : ControllerBase { }

// No deprecation notice
```

**Correct**:

```csharp
// Mark as deprecated
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("1.0", Deprecated = true)] // Marked as deprecated
public class ProductsV1Controller : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<List<Product>>> GetProducts()
    {
        // Still works, but clients should migrate
        Response.Headers.Add("Deprecation", "true");
        Response.Headers.Add("Sunset", "2025-12-31"); // Removal date
        Response.Headers.Add("Link", "</api/v2/products>; rel=\"successor-version\"");
        
        return Ok(await _service.GetAllAsync());
    }
}

// Or use middleware to add deprecation headers
public class DeprecationMiddleware
{
    private readonly RequestDelegate _next;

    public DeprecationMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var apiVersion = context.GetRequestedApiVersion();
        
        if (apiVersion?.MajorVersion == 1)
        {
            context.Response.Headers.Add("Deprecation", "true");
            context.Response.Headers.Add("Sunset", "2025-12-31");
            context.Response.Headers.Add("Link", 
                "</api/v2/products>; rel=\"successor-version\"");
        }

        await _next(context);
    }
}
```

**Why**:
- Gives clients time to migrate
- Prevents sudden breaking changes
- Industry standard deprecation headers
- Better developer experience

---

### Rule 4: Version Controllers, Not Individual Actions

**Priority**: High

**Description**: Version at the controller level, not individual actions (unless necessary).

**Incorrect**:

```csharp
// Versioning individual actions - confusing
[ApiController]
[Route("api/products")]
public class ProductsController : ControllerBase
{
    [HttpGet]
    [ApiVersion("1.0")]
    public async Task<ActionResult> GetProductsV1() { }

    [HttpGet]
    [ApiVersion("2.0")]
    public async Task<ActionResult> GetProductsV2() { }

    [HttpPost]
    [ApiVersion("1.0")]
    public async Task<ActionResult> CreateProductV1() { }

    [HttpPost]
    [ApiVersion("2.0")]
    public async Task<ActionResult> CreateProductV2() { }
}
```

**Correct**:

```csharp
// Version entire controllers
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("1.0")]
public class ProductsV1Controller : ControllerBase
{
    private readonly IProductService _service;

    public ProductsV1Controller(IProductService service)
    {
        _service = service;
    }

    [HttpGet]
    public async Task<ActionResult<List<Product>>> GetProducts()
    {
        return Ok(await _service.GetAllAsync());
    }

    [HttpPost]
    public async Task<ActionResult<Product>> CreateProduct(CreateProductRequest request)
    {
        var product = await _service.CreateAsync(request);
        return CreatedAtAction(nameof(GetProducts), new { id = product.Id }, product);
    }
}

[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("2.0")]
public class ProductsV2Controller : ControllerBase
{
    private readonly IProductService _service;

    public ProductsV2Controller(IProductService service)
    {
        _service = service;
    }

    [HttpGet]
    public async Task<ActionResult<PagedResponse<ProductDto>>> GetProducts(
        [FromQuery] PaginationParams pagination)
    {
        return Ok(await _service.GetPagedAsync(pagination));
    }

    [HttpPost]
    public async Task<ActionResult<ProductDto>> CreateProduct(CreateProductRequest request)
    {
        var product = await _service.CreateAsync(request);
        return CreatedAtAction(nameof(GetProducts), new { id = product.Id }, product);
    }
}
```

**Why**:
- Clearer organization
- Easier to maintain
- All actions in a version together
- Better for testing

---

### Rule 5: Document Version Differences

**Priority**: Medium

**Description**: Clearly document what changed between versions in Swagger/OpenAPI.

**Correct**:

```csharp
// Swagger configuration with versioning
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Version = "v1",
        Title = "Products API",
        Description = "Version 1.0 - Returns Product entities directly",
        Contact = new OpenApiContact { Name = "API Support", Email = "support@example.com" }
    });

    options.SwaggerDoc("v2", new OpenApiInfo
    {
        Version = "v2",
        Title = "Products API",
        Description = "Version 2.0 - Returns ProductDto with pagination support. " +
                      "Breaking changes: Response format changed, pagination required.",
        Contact = new OpenApiContact { Name = "API Support", Email = "support@example.com" }
    });

    // Resolve versioned endpoints
    options.DocInclusionPredicate((version, desc) =>
    {
        if (!desc.TryGetMethodInfo(out var methodInfo))
            return false;

        var versions = methodInfo.DeclaringType!
            .GetCustomAttributes(true)
            .OfType<ApiVersionAttribute>()
            .SelectMany(attr => attr.Versions);

        return versions.Any(v => $"v{v}" == version);
    });
});

// In controller, document version-specific behavior
[ApiController]
[Route("api/v{version:apiVersion}/products")]
[ApiVersion("2.0")]
[Produces("application/json")]
public class ProductsV2Controller : ControllerBase
{
    /// <summary>
    /// Gets a paginated list of products (v2.0)
    /// </summary>
    /// <remarks>
    /// Version 2.0 changes:
    /// - Returns ProductDto instead of Product
    /// - Requires pagination parameters
    /// - Includes total count and page information
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResponse<ProductDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<PagedResponse<ProductDto>>> GetProducts(
        [FromQuery] PaginationParams pagination)
    {
        return Ok(await _service.GetPagedAsync(pagination));
    }
}
```

**Why**:
- Helps clients understand changes
- Reduces migration effort
- Better API documentation
- Clearer upgrade path

---

## Integration Example

Complete versioning setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

// Add API versioning
builder.Services.AddApiVersioning(options =>
{
    options.DefaultApiVersion = new ApiVersion(1, 0);
    options.AssumeDefaultVersionWhenUnspecified = true;
    options.ReportApiVersions = true;
    options.ApiVersionReader = ApiVersionReader.Combine(
        new UrlSegmentApiVersionReader(),
        new QueryStringApiVersionReader("version"),
        new HeaderApiVersionReader("X-Version")
    );
})
.AddApiExplorer(options =>
{
    options.GroupNameFormat = "'v'VVV";
    options.SubstituteApiVersionInUrl = true;
});

// Swagger with versioning
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Version = "v1",
        Title = "Products API v1",
        Description = "Version 1.0 API"
    });

    options.SwaggerDoc("v2", new OpenApiInfo
    {
        Version = "v2",
        Title = "Products API v2",
        Description = "Version 2.0 API with pagination"
    });
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "API v1");
        options.SwaggerEndpoint("/swagger/v2/swagger.json", "API v2");
    });
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] Versioning strategy chosen (URL path recommended)
- [ ] Semantic versioning used (MAJOR.MINOR)
- [ ] Default version configured
- [ ] Deprecated versions marked
- [ ] Version differences documented
- [ ] Swagger configured for multiple versions
- [ ] Migration path provided for clients

## References

- [API Versioning in ASP.NET Core](https://docs.microsoft.com/aspnet/core/web-api/versioning)
- [Semantic Versioning](https://semver.org/)
- [RFC 8594 - The Sunset HTTP Header](https://datatracker.ietf.org/doc/html/rfc8594)

## Changelog

### v1.0.0
- Initial release
- 5 core rules for API versioning
