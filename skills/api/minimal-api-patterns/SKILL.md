---
name: minimal-api-patterns
description: Best practices for building ASP.NET Core Minimal APIs including endpoint organization, validation, dependency injection, and route grouping.
version: 1.0.0
priority: high
categories:
  - api
  - minimal-api
use_when:
  - "When building Minimal APIs in ASP.NET Core"
  - "When migrating from controllers to Minimal APIs"
  - "When organizing Minimal API endpoints"
  - "When implementing validation in Minimal APIs"
prerequisites:
  - "ASP.NET Core 8.0+"
related_skills:
  - webapi-best-practices
  - input-validation
---

# Minimal API Patterns

## Overview

This skill covers best practices for building ASP.NET Core Minimal APIs. Minimal APIs provide a lightweight alternative to controllers, but require careful organization to maintain code quality and testability.

## Rules

### Rule 1: Organize Endpoints with Route Groups

**Priority**: High

**Description**: Use route groups to organize related endpoints and apply common configuration.

**Incorrect**:

```csharp
// All endpoints in Program.cs - hard to maintain
var app = builder.Build();

app.MapGet("/api/products", async (AppDbContext db) =>
    await db.Products.ToListAsync());

app.MapGet("/api/products/{id}", async (int id, AppDbContext db) =>
    await db.Products.FindAsync(id));

app.MapPost("/api/products", async (Product product, AppDbContext db) =>
{
    db.Products.Add(product);
    await db.SaveChangesAsync();
    return Results.Created($"/api/products/{product.Id}", product);
});

app.MapGet("/api/orders", async (AppDbContext db) =>
    await db.Orders.ToListAsync());
// ... many more endpoints
```

**Correct**:

```csharp
// Program.cs - Use route groups
var app = builder.Build();

// Product endpoints group
var productsGroup = app.MapGroup("/api/products")
    .WithTags("Products")
    .WithOpenApi();

productsGroup.MapGet("/", async (IProductService service) =>
    await service.GetAllAsync());

productsGroup.MapGet("/{id:int}", async (int id, IProductService service) =>
{
    var product = await service.GetByIdAsync(id);
    return product is null ? Results.NotFound() : Results.Ok(product);
});

productsGroup.MapPost("/", async (CreateProductRequest request, IProductService service) =>
{
    var product = await service.CreateAsync(request);
    return Results.Created($"/api/products/{product.Id}", product);
})
.Produces<ProductDto>(StatusCodes.Status201Created)
.ProducesValidationProblem();

// Order endpoints group
var ordersGroup = app.MapGroup("/api/orders")
    .WithTags("Orders")
    .RequireAuthorization()
    .WithOpenApi();

ordersGroup.MapGet("/", async (IOrderService service) =>
    await service.GetAllAsync());

// Or extract to extension methods
app.MapProductEndpoints();
app.MapOrderEndpoints();
```

**Why**:
- Route groups improve organization
- Shared configuration (auth, tags, OpenAPI) applied once
- Easier to test and maintain
- Better Swagger documentation

---

### Rule 2: Use Dependency Injection Properly

**Priority**: High

**Description**: Inject services through parameters. Use service locator pattern only when necessary.

**Incorrect**:

```csharp
// Service locator anti-pattern
app.MapGet("/products", async (HttpContext context) =>
{
    var db = context.RequestServices.GetRequiredService<AppDbContext>();
    return await db.Products.ToListAsync();
});

// Manual service creation
app.MapGet("/products", async () =>
{
    var db = new AppDbContext(); // Wrong! No DI, no disposal
    return await db.Products.ToListAsync();
});
```

**Correct**:

```csharp
// Direct injection - preferred
app.MapGet("/products", async (AppDbContext db) =>
    await db.Products.ToListAsync());

// Multiple services
app.MapPost("/orders", async (
    CreateOrderRequest request,
    IOrderService orderService,
    ILogger<Program> logger) =>
{
    logger.LogInformation("Creating order");
    var order = await orderService.CreateAsync(request);
    return Results.Created($"/api/orders/{order.Id}", order);
});

// Using IResult for complex scenarios
app.MapGet("/products/{id:int}", async (
    int id,
    IProductService service,
    ILogger<Program> logger) =>
{
    var product = await service.GetByIdAsync(id);
    
    if (product is null)
    {
        logger.LogWarning("Product {ProductId} not found", id);
        return Results.NotFound();
    }
    
    return Results.Ok(product);
})
.Produces<ProductDto>()
.Produces(StatusCodes.Status404NotFound);
```

**Why**:
- DI provides proper lifecycle management
- Services are testable and mockable
- No manual disposal needed
- Follows ASP.NET Core patterns

---

### Rule 3: Implement Proper Validation

**Priority**: High

**Description**: Use FluentValidation or Data Annotations for input validation in Minimal APIs.

**Incorrect**:

```csharp
// No validation
app.MapPost("/products", async (CreateProductRequest request, AppDbContext db) =>
{
    // Request could have invalid data
    var product = new Product { Name = request.Name, Price = request.Price };
    db.Products.Add(product);
    await db.SaveChangesAsync();
    return Results.Created($"/api/products/{product.Id}", product);
});

// Manual validation - error-prone
app.MapPost("/products", async (CreateProductRequest request, AppDbContext db) =>
{
    if (string.IsNullOrEmpty(request.Name))
        return Results.BadRequest("Name is required");
    if (request.Price <= 0)
        return Results.BadRequest("Price must be positive");
    // ... more manual checks
});
```

**Correct**:

```csharp
// Using Data Annotations
public record CreateProductRequest
{
    [Required]
    [StringLength(200)]
    public required string Name { get; init; }

    [Range(0.01, 999999.99)]
    public decimal Price { get; init; }
}

// Enable validation
app.MapPost("/products", async (
    [FromBody] CreateProductRequest request,
    IProductService service) =>
{
    var product = await service.CreateAsync(request);
    return Results.Created($"/api/products/{product.Id}", product);
})
.ProducesValidationProblem()
.Produces<ProductDto>(StatusCodes.Status201Created);

// Or use FluentValidation
builder.Services.AddScoped<IValidator<CreateProductRequest>, CreateProductRequestValidator>();

app.MapPost("/products", async (
    CreateProductRequest request,
    IValidator<CreateProductRequest> validator,
    IProductService service) =>
{
    var validationResult = await validator.ValidateAsync(request);
    if (!validationResult.IsValid)
    {
        return Results.ValidationProblem(validationResult.ToDictionary());
    }

    var product = await service.CreateAsync(request);
    return Results.Created($"/api/products/{product.Id}", product);
});
```

**Why**:
- Consistent validation across endpoints
- Automatic ProblemDetails responses
- Reusable validation rules
- Better error messages

---

### Rule 4: Use Typed Results

**Priority**: Medium

**Description**: Use TypedResults for better type safety and OpenAPI documentation.

**Incorrect**:

```csharp
// Using Results.* methods - no type information
app.MapGet("/products/{id:int}", async (int id, IProductService service) =>
{
    var product = await service.GetByIdAsync(id);
    return product is null ? Results.NotFound() : Results.Ok(product);
});
```

**Correct**:

```csharp
// Using TypedResults - type-safe
app.MapGet("/products/{id:int}", async Task<Results<Ok<ProductDto>, NotFound>> (
    int id,
    IProductService service) =>
{
    var product = await service.GetByIdAsync(id);
    return product is null ? TypedResults.NotFound() : TypedResults.Ok(product);
})
.Produces<ProductDto>()
.Produces(StatusCodes.Status404NotFound);

// Multiple result types
app.MapPost("/products", async Task<Results<Created<ProductDto>, BadRequest, ValidationProblem>> (
    CreateProductRequest request,
    IProductService service) =>
{
    var product = await service.CreateAsync(request);
    return TypedResults.Created($"/api/products/{product.Id}", product);
})
.Produces<ProductDto>(StatusCodes.Status201Created)
.ProducesValidationProblem();
```

**Why**:
- Compile-time type checking
- Better IntelliSense
- Automatic OpenAPI schema generation
- Self-documenting code

---

### Rule 5: Extract Endpoint Definitions

**Priority**: High

**Description**: Move endpoint definitions to separate classes or extension methods for better organization.

**Incorrect**:

```csharp
// All endpoints in Program.cs - becomes unmaintainable
var app = builder.Build();

app.MapGet("/api/products", ...);
app.MapGet("/api/products/{id}", ...);
app.MapPost("/api/products", ...);
app.MapPut("/api/products/{id}", ...);
app.MapDelete("/api/products/{id}", ...);

app.MapGet("/api/orders", ...);
// ... 100+ more endpoints
```

**Correct**:

```csharp
// Extension method approach
public static class ProductEndpoints
{
    public static void MapProductEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/products")
            .WithTags("Products")
            .WithOpenApi();

        group.MapGet("/", GetAllProducts)
            .Produces<List<ProductDto>>();

        group.MapGet("/{id:int}", GetProduct)
            .Produces<ProductDto>()
            .Produces(StatusCodes.Status404NotFound);

        group.MapPost("/", CreateProduct)
            .Produces<ProductDto>(StatusCodes.Status201Created)
            .ProducesValidationProblem();

        group.MapPut("/{id:int}", UpdateProduct)
            .Produces<ProductDto>()
            .Produces(StatusCodes.Status404NotFound);

        group.MapDelete("/{id:int}", DeleteProduct)
            .Produces(StatusCodes.Status204NoContent)
            .Produces(StatusCodes.Status404NotFound);
    }

    private static async Task<Results<Ok<List<ProductDto>>, NotFound>> GetAllProducts(
        IProductService service)
    {
        var products = await service.GetAllAsync();
        return TypedResults.Ok(products);
    }

    private static async Task<Results<Ok<ProductDto>, NotFound>> GetProduct(
        int id,
        IProductService service)
    {
        var product = await service.GetByIdAsync(id);
        return product is null 
            ? TypedResults.NotFound() 
            : TypedResults.Ok(product);
    }

    private static async Task<Results<Created<ProductDto>, BadRequest, ValidationProblem>> CreateProduct(
        CreateProductRequest request,
        IProductService service)
    {
        var product = await service.CreateAsync(request);
        return TypedResults.Created($"/api/products/{product.Id}", product);
    }

    private static async Task<Results<Ok<ProductDto>, NotFound>> UpdateProduct(
        int id,
        UpdateProductRequest request,
        IProductService service)
    {
        var product = await service.UpdateAsync(id, request);
        return product is null 
            ? TypedResults.NotFound() 
            : TypedResults.Ok(product);
    }

    private static async Task<Results<NoContent, NotFound>> DeleteProduct(
        int id,
        IProductService service)
    {
        var deleted = await service.DeleteAsync(id);
        return deleted 
            ? TypedResults.NoContent() 
            : TypedResults.NotFound();
    }
}

// Program.cs
var app = builder.Build();
app.MapProductEndpoints();
app.MapOrderEndpoints();
app.Run();
```

**Why**:
- Better code organization
- Easier to test endpoints
- Reusable endpoint groups
- Maintainable as project grows

---

### Rule 6: Handle Errors Consistently

**Priority**: High

**Description**: Use exception handling middleware or IResult for consistent error responses.

**Incorrect**:

```csharp
// Inconsistent error handling
app.MapGet("/products/{id}", async (int id, AppDbContext db) =>
{
    try
    {
        var product = await db.Products.FindAsync(id);
        if (product == null)
            return Results.Json(new { error = "Not found" }, statusCode: 404);
        return Results.Ok(product);
    }
    catch (Exception ex)
    {
        return Results.Json(new { error = ex.Message }, statusCode: 500);
    }
});
```

**Correct**:

```csharp
// Global exception handler
app.UseExceptionHandler(exceptionHandlerApp =>
{
    exceptionHandlerApp.Run(async context =>
    {
        var exceptionHandler = context.Features.Get<IExceptionHandlerFeature>();
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        
        logger.LogError(exceptionHandler?.Error, "Unhandled exception");

        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/json";

        var problemDetails = new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "An error occurred",
            Detail = app.Environment.IsDevelopment() 
                ? exceptionHandler?.Error?.Message 
                : "An unexpected error occurred"
        };

        await context.Response.WriteAsJsonAsync(problemDetails);
    });
});

// Endpoints return appropriate results
app.MapGet("/products/{id:int}", async (
    int id,
    IProductService service,
    ILogger<Program> logger) =>
{
    try
    {
        var product = await service.GetByIdAsync(id);
        return product is null 
            ? TypedResults.NotFound() 
            : TypedResults.Ok(product);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error retrieving product {ProductId}", id);
        throw; // Let middleware handle it
    }
});
```

**Why**:
- Consistent error format
- Centralized error handling
- Proper logging
- RFC 7807 ProblemDetails

---

## Integration Example

Complete Minimal API setup:

```csharp
// Program.cs
using Microsoft.AspNetCore.Diagnostics;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddScoped<IProductService, ProductService>();
builder.Services.AddScoped<IOrderService, OrderService>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(/* ... */);

builder.Services.AddAuthorization();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Middleware
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();

// Exception handling
app.UseExceptionHandler(exceptionHandlerApp =>
{
    exceptionHandlerApp.Run(async context =>
    {
        var exceptionHandler = context.Features.Get<IExceptionHandlerFeature>();
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        
        logger.LogError(exceptionHandler?.Error, "Unhandled exception");

        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/json";

        await context.Response.WriteAsJsonAsync(new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "An error occurred",
            Detail = app.Environment.IsDevelopment() 
                ? exceptionHandler?.Error?.Message 
                : "An unexpected error occurred"
        });
    });
});

// Endpoints
app.MapProductEndpoints();
app.MapOrderEndpoints();

app.MapHealthChecks("/health").AllowAnonymous();

app.Run();
```

## Checklist

- [ ] Endpoints organized with route groups
- [ ] Services injected via DI (not service locator)
- [ ] Validation implemented (FluentValidation or Data Annotations)
- [ ] TypedResults used for type safety
- [ ] Endpoints extracted to separate classes
- [ ] Consistent error handling
- [ ] OpenAPI documentation configured
- [ ] Authorization applied where needed

## References

- [Minimal APIs Documentation](https://docs.microsoft.com/aspnet/core/fundamentals/minimal-apis)
- [Route Groups](https://docs.microsoft.com/aspnet/core/fundamentals/minimal-apis/route-groups)
- [Typed Results](https://docs.microsoft.com/aspnet/core/fundamentals/minimal-apis/responses#typedresults)

## Changelog

### v1.0.0
- Initial release
- 6 core rules for Minimal APIs
