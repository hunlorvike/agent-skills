---
name: openapi-swagger
description: Best practices for documenting ASP.NET Core APIs with OpenAPI/Swagger including proper schemas, examples, and security definitions.
version: 1.0.0
priority: medium
categories:
  - api
  - documentation
  - openapi
use_when:
  - "When documenting REST APIs"
  - "When setting up Swagger UI"
  - "When generating API clients"
  - "When publishing API documentation"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Swashbuckle.AspNetCore"
related_skills:
  - webapi-best-practices
  - api-versioning
---

# OpenAPI/Swagger Best Practices

## Overview

This skill covers best practices for documenting ASP.NET Core APIs with OpenAPI/Swagger. Good API documentation improves developer experience and enables code generation.

## Rules

### Rule 1: Provide Complete Operation Documentation

**Priority**: High

**Description**: Document all endpoints with summaries, descriptions, and response types.

**Incorrect**:

```csharp
// No documentation
[HttpGet("{id}")]
public async Task<IActionResult> GetProduct(int id)
{
    return Ok(await _service.GetByIdAsync(id));
}
```

**Correct**:

```csharp
/// <summary>
/// Gets a product by ID
/// </summary>
/// <param name="id">The product identifier</param>
/// <returns>The product if found</returns>
/// <response code="200">Returns the requested product</response>
/// <response code="404">Product not found</response>
[HttpGet("{id:int}")]
[ProducesResponseType(typeof(ProductDto), StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
public async Task<ActionResult<ProductDto>> GetProduct(int id)
{
    var product = await _service.GetByIdAsync(id);
    if (product is null)
        return NotFound();
    return Ok(product);
}
```

**Why**:
- Auto-generates Swagger documentation
- Better developer experience
- Enables client code generation
- Self-documenting APIs

---

### Rule 2: Include Request/Response Examples

**Priority**: Medium

**Description**: Provide examples for complex request/response models.

**Correct**:

```csharp
/// <summary>
/// Creates a new product
/// </summary>
/// <param name="request">Product creation data</param>
/// <returns>The created product</returns>
/// <response code="201">Product created successfully</response>
/// <response code="400">Invalid request data</response>
[HttpPost]
[ProducesResponseType(typeof(ProductDto), StatusCodes.Status201Created)]
[ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
public async Task<ActionResult<ProductDto>> CreateProduct(
    [FromBody] CreateProductRequest request)
{
    var product = await _service.CreateAsync(request);
    return CreatedAtAction(nameof(GetProduct), new { id = product.Id }, product);
}

// Add examples to DTOs
public record CreateProductRequest
{
    /// <summary>
    /// Product name
    /// </summary>
    /// <example>Laptop Pro 15"</example>
    [Required]
    [StringLength(200)]
    public required string Name { get; init; }

    /// <summary>
    /// Product price in USD
    /// </summary>
    /// <example>1299.99</example>
    [Required]
    [Range(0.01, 999999.99)]
    public decimal Price { get; init; }
}

// Or use Swagger examples
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo { /* ... */ });
    
    options.SchemaFilter<ExampleSchemaFilter>();
});

public class ExampleSchemaFilter : ISchemaFilter
{
    public void Apply(OpenApiSchema schema, SchemaFilterContext context)
    {
        if (context.Type == typeof(CreateProductRequest))
        {
            schema.Example = new OpenApiObject
            {
                ["name"] = new OpenApiString("Laptop Pro 15\""),
                ["price"] = new OpenApiDouble(1299.99),
                ["description"] = new OpenApiString("High-performance laptop")
            };
        }
    }
}
```

**Why**:
- Helps developers understand expected format
- Reduces trial and error
- Better API exploration
- Clearer documentation

---

### Rule 3: Configure Security Schemes

**Priority**: High

**Description**: Document authentication requirements in Swagger.

**Correct**:

```csharp
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Products API",
        Version = "v1",
        Description = "API for managing products"
    });

    // Add JWT Bearer authentication
    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization header using the Bearer scheme. " +
                      "Enter 'Bearer' [space] and then your token in the text input below.",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer",
        BearerFormat = "JWT"
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});
```

**Why**:
- Enables testing authenticated endpoints in Swagger UI
- Documents security requirements
- Better developer experience
- Clear security expectations

---

### Rule 4: Organize with Tags

**Priority**: Medium

**Description**: Use tags to group related endpoints in Swagger UI.

**Correct**:

```csharp
[ApiController]
[Route("api/[controller]")]
[Tags("Products")] // Group in Swagger
public class ProductsController : ControllerBase
{
    [HttpGet]
    [Tags("Products", "Public")] // Multiple tags
    public async Task<ActionResult<List<ProductDto>>> GetProducts()
    {
        return Ok(await _service.GetAllAsync());
    }
}

// Or configure tags globally
builder.Services.AddSwaggerGen(options =>
{
    options.TagActionsBy(api => new[] { api.GroupName ?? api.ActionDescriptor.RouteValues["controller"] });
    options.DocInclusionPredicate((name, api) => true);
});
```

**Why**:
- Better organization in Swagger UI
- Easier to find endpoints
- Logical grouping
- Improved navigation

---

## Integration Example

Complete Swagger configuration:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Version = "v1",
        Title = "Products API",
        Description = "API for managing products",
        Contact = new OpenApiContact
        {
            Name = "API Support",
            Email = "support@example.com"
        },
        License = new OpenApiLicense
        {
            Name = "MIT",
            Url = new Uri("https://opensource.org/licenses/MIT")
        }
    });

    // Security
    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization header",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });

    // Include XML comments
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    options.IncludeXmlComments(xmlPath);

    // Custom schema filters
    options.SchemaFilter<ExampleSchemaFilter>();
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "Products API v1");
        options.RoutePrefix = string.Empty; // Swagger at root
    });
}

app.Run();
```

## Checklist

- [ ] All endpoints documented with XML comments
- [ ] Response types specified with ProducesResponseType
- [ ] Examples provided for complex models
- [ ] Security schemes configured
- [ ] Tags used for organization
- [ ] XML comments included in build
- [ ] Swagger UI configured for development

## References

- [Swagger/OpenAPI in ASP.NET Core](https://docs.microsoft.com/aspnet/core/tutorials/web-api-help-pages-using-swagger)
- [OpenAPI Specification](https://swagger.io/specification/)

## Changelog

### v1.0.0
- Initial release
- 4 core rules for OpenAPI/Swagger
