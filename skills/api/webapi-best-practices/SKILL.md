---
name: webapi-best-practices
description: Best practices for designing and implementing RESTful Web APIs in ASP.NET Core, including proper HTTP status codes, DTOs, error handling, pagination, and API conventions.
version: 1.0.0
priority: critical
categories:
  - api
  - design
  - rest
use_when:
  - "When reviewing ASP.NET Web API controllers"
  - "When creating new REST endpoints"
  - "When refactoring existing API code"
  - "When designing API contracts"
  - "When handling API responses and errors"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.AspNetCore.Mvc"
related_skills:
  - minimal-api-patterns
  - api-versioning
  - openapi-swagger
  - input-validation
---

# Web API Best Practices

## Overview

This skill covers essential best practices for building robust, maintainable, and standards-compliant REST APIs in ASP.NET Core. It addresses common mistakes and provides patterns for:

- Proper HTTP status code usage
- Request/response DTOs
- Consistent error handling
- Pagination and filtering
- Route design conventions
- Action result types

## Rules

### Rule 1: Use Appropriate HTTP Status Codes

**Priority**: Critical

**Description**: Return the correct HTTP status code for each operation. Don't return 200 OK for everything.

**Incorrect**:

```csharp
[HttpGet("{id}")]
public async Task<IActionResult> GetOrder(int id)
{
    var order = await _repository.GetByIdAsync(id);
    return Ok(order); // Returns 200 even when order is null
}

[HttpPost]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    var order = await _service.CreateAsync(request);
    return Ok(order); // Should return 201 Created
}

[HttpDelete("{id}")]
public async Task<IActionResult> DeleteOrder(int id)
{
    await _repository.DeleteAsync(id);
    return Ok(); // Should return 204 No Content
}
```

**Correct**:

```csharp
[HttpGet("{id}")]
[ProducesResponseType(typeof(OrderDto), StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
public async Task<ActionResult<OrderDto>> GetOrder(int id)
{
    var order = await _repository.GetByIdAsync(id);
    if (order is null)
        return NotFound();
    
    return Ok(_mapper.Map<OrderDto>(order));
}

[HttpPost]
[ProducesResponseType(typeof(OrderDto), StatusCodes.Status201Created)]
[ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
{
    var order = await _service.CreateAsync(request);
    return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
}

[HttpDelete("{id}")]
[ProducesResponseType(StatusCodes.Status204NoContent)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
public async Task<IActionResult> DeleteOrder(int id)
{
    var exists = await _repository.ExistsAsync(id);
    if (!exists)
        return NotFound();
    
    await _repository.DeleteAsync(id);
    return NoContent();
}
```

**Why**: Correct status codes are essential for RESTful API design:
- **200 OK**: Successful GET, PUT, PATCH
- **201 Created**: Successful POST (resource created)
- **204 No Content**: Successful DELETE or PUT with no response body
- **400 Bad Request**: Invalid input/validation errors
- **404 Not Found**: Resource doesn't exist
- **409 Conflict**: Resource conflict (e.g., duplicate)
- **500 Internal Server Error**: Unhandled server errors

---

### Rule 2: Use DTOs Instead of Domain Entities

**Priority**: Critical

**Description**: Never expose domain entities directly in API responses. Use Data Transfer Objects (DTOs) to control what data is exposed.

**Incorrect**:

```csharp
// Exposing domain entity directly
[HttpGet("{id}")]
public async Task<ActionResult<Order>> GetOrder(int id)
{
    var order = await _context.Orders
        .Include(o => o.Customer)
        .Include(o => o.Items)
        .FirstOrDefaultAsync(o => o.Id == id);
    
    return Ok(order); // Exposes entire entity graph, including sensitive data
}

// Domain entity with sensitive data
public class Order
{
    public int Id { get; set; }
    public string CustomerEmail { get; set; }
    public decimal InternalCost { get; set; } // Should not be exposed
    public Customer Customer { get; set; } // Circular reference issues
}
```

**Correct**:

```csharp
// Use DTOs for API contracts
public record OrderDto(
    int Id,
    string OrderNumber,
    DateTime CreatedAt,
    string Status,
    decimal TotalAmount,
    IReadOnlyList<OrderItemDto> Items
);

public record OrderItemDto(
    int ProductId,
    string ProductName,
    int Quantity,
    decimal UnitPrice
);

[HttpGet("{id}")]
public async Task<ActionResult<OrderDto>> GetOrder(int id)
{
    var order = await _context.Orders
        .Where(o => o.Id == id)
        .Select(o => new OrderDto(
            o.Id,
            o.OrderNumber,
            o.CreatedAt,
            o.Status.ToString(),
            o.TotalAmount,
            o.Items.Select(i => new OrderItemDto(
                i.ProductId,
                i.Product.Name,
                i.Quantity,
                i.UnitPrice
            )).ToList()
        ))
        .FirstOrDefaultAsync();
    
    if (order is null)
        return NotFound();
    
    return Ok(order);
}
```

**Why**:
- **Security**: Prevents exposing sensitive internal data
- **Stability**: API contract is decoupled from domain model changes
- **Performance**: Control exactly what data is serialized
- **Serialization**: Avoids circular reference issues
- **Versioning**: Easier to version APIs with separate DTOs

---

### Rule 3: Use Typed Action Results

**Priority**: High

**Description**: Use `ActionResult<T>` instead of just `IActionResult` to get compile-time type checking and better OpenAPI documentation.

**Incorrect**:

```csharp
[HttpGet("{id}")]
public async Task<IActionResult> GetProduct(int id)
{
    var product = await _repository.GetByIdAsync(id);
    if (product == null)
        return NotFound();
    return Ok(product); // No type information
}

[HttpGet]
public async Task<IActionResult> GetProducts()
{
    var products = await _repository.GetAllAsync();
    return Ok(products); // Return type unknown
}
```

**Correct**:

```csharp
[HttpGet("{id}")]
[ProducesResponseType(typeof(ProductDto), StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
public async Task<ActionResult<ProductDto>> GetProduct(int id)
{
    var product = await _repository.GetByIdAsync(id);
    if (product is null)
        return NotFound();
    
    return _mapper.Map<ProductDto>(product);
}

[HttpGet]
[ProducesResponseType(typeof(IEnumerable<ProductDto>), StatusCodes.Status200OK)]
public async Task<ActionResult<IEnumerable<ProductDto>>> GetProducts()
{
    var products = await _repository.GetAllAsync();
    return Ok(_mapper.Map<IEnumerable<ProductDto>>(products));
}
```

**Why**:
- Compile-time type safety
- Better IntelliSense support
- Automatic OpenAPI schema generation
- Self-documenting code

---

### Rule 4: Implement Consistent Error Handling

**Priority**: Critical

**Description**: Use a global exception handler and return consistent error responses using ProblemDetails.

**Incorrect**:

```csharp
[HttpGet("{id}")]
public async Task<ActionResult<OrderDto>> GetOrder(int id)
{
    try
    {
        var order = await _service.GetOrderAsync(id);
        return Ok(order);
    }
    catch (Exception ex)
    {
        // Exposing internal error details
        return BadRequest(new { error = ex.Message, stackTrace = ex.StackTrace });
    }
}
```

**Correct**:

```csharp
// Program.cs - Configure ProblemDetails
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        context.ProblemDetails.Extensions["traceId"] = context.HttpContext.TraceIdentifier;
    };
});

// Global Exception Handler Middleware
public class GlobalExceptionHandler : IExceptionHandler
{
    private readonly ILogger<GlobalExceptionHandler> _logger;

    public GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger)
    {
        _logger = logger;
    }

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        _logger.LogError(exception, "Unhandled exception occurred");

        var problemDetails = exception switch
        {
            NotFoundException => new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Title = "Resource not found",
                Detail = exception.Message
            },
            ValidationException validationEx => new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Validation failed",
                Detail = validationEx.Message,
                Extensions = { ["errors"] = validationEx.Errors }
            },
            _ => new ProblemDetails
            {
                Status = StatusCodes.Status500InternalServerError,
                Title = "An error occurred",
                Detail = "An unexpected error occurred. Please try again later."
            }
        };

        httpContext.Response.StatusCode = problemDetails.Status ?? 500;
        await httpContext.Response.WriteAsJsonAsync(problemDetails, cancellationToken);
        return true;
    }
}

// Program.cs registration
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
app.UseExceptionHandler();
```

**Why**:
- Consistent error format across all endpoints
- No sensitive information leaked
- RFC 7807 compliant (ProblemDetails)
- Centralized error logging
- Better client experience

---

### Rule 5: Implement Pagination for List Endpoints

**Priority**: High

**Description**: Always implement pagination for endpoints that return collections to prevent performance issues and improve client experience.

**Incorrect**:

```csharp
[HttpGet]
public async Task<ActionResult<IEnumerable<ProductDto>>> GetProducts()
{
    // Returns ALL products - can be millions of records
    var products = await _context.Products.ToListAsync();
    return Ok(products);
}
```

**Correct**:

```csharp
// Pagination request model
public record PaginationParams(
    int PageNumber = 1,
    int PageSize = 10
)
{
    public int PageNumber { get; init; } = PageNumber < 1 ? 1 : PageNumber;
    public int PageSize { get; init; } = PageSize > 100 ? 100 : (PageSize < 1 ? 10 : PageSize);
}

// Paginated response model
public record PagedResponse<T>(
    IReadOnlyList<T> Items,
    int PageNumber,
    int PageSize,
    int TotalCount,
    int TotalPages
)
{
    public bool HasPreviousPage => PageNumber > 1;
    public bool HasNextPage => PageNumber < TotalPages;
}

[HttpGet]
[ProducesResponseType(typeof(PagedResponse<ProductDto>), StatusCodes.Status200OK)]
public async Task<ActionResult<PagedResponse<ProductDto>>> GetProducts(
    [FromQuery] PaginationParams pagination,
    [FromQuery] string? search = null,
    [FromQuery] string? sortBy = null,
    [FromQuery] bool descending = false)
{
    var query = _context.Products.AsNoTracking();

    // Apply search filter
    if (!string.IsNullOrWhiteSpace(search))
    {
        query = query.Where(p => p.Name.Contains(search) || 
                                  p.Description.Contains(search));
    }

    // Apply sorting
    query = sortBy?.ToLower() switch
    {
        "name" => descending ? query.OrderByDescending(p => p.Name) : query.OrderBy(p => p.Name),
        "price" => descending ? query.OrderByDescending(p => p.Price) : query.OrderBy(p => p.Price),
        "created" => descending ? query.OrderByDescending(p => p.CreatedAt) : query.OrderBy(p => p.CreatedAt),
        _ => query.OrderBy(p => p.Id)
    };

    var totalCount = await query.CountAsync();
    var totalPages = (int)Math.Ceiling(totalCount / (double)pagination.PageSize);

    var items = await query
        .Skip((pagination.PageNumber - 1) * pagination.PageSize)
        .Take(pagination.PageSize)
        .Select(p => new ProductDto(p.Id, p.Name, p.Price, p.Description))
        .ToListAsync();

    return Ok(new PagedResponse<ProductDto>(
        items,
        pagination.PageNumber,
        pagination.PageSize,
        totalCount,
        totalPages
    ));
}
```

**Why**:
- Prevents memory exhaustion with large datasets
- Improves response times
- Better user experience with incremental loading
- Reduces bandwidth usage
- Standard practice for professional APIs

---

### Rule 6: Use Proper Route Design

**Priority**: High

**Description**: Follow RESTful routing conventions with proper resource naming and HTTP verb usage.

**Incorrect**:

```csharp
// Bad route design
[Route("api")]
public class OrderController : ControllerBase
{
    [HttpGet("getOrders")]           // Verb in URL
    public Task<IActionResult> GetOrders() { }
    
    [HttpGet("getOrderById/{id}")]   // Redundant naming
    public Task<IActionResult> GetOrderById(int id) { }
    
    [HttpPost("createOrder")]        // POST + verb = redundant
    public Task<IActionResult> CreateOrder() { }
    
    [HttpPost("deleteOrder/{id}")]   // Wrong HTTP verb
    public Task<IActionResult> DeleteOrder(int id) { }
}
```

**Correct**:

```csharp
[ApiController]
[Route("api/v1/orders")]
[Produces("application/json")]
public class OrdersController : ControllerBase
{
    // GET api/v1/orders
    [HttpGet]
    public async Task<ActionResult<PagedResponse<OrderDto>>> GetOrders(
        [FromQuery] PaginationParams pagination) { }
    
    // GET api/v1/orders/5
    [HttpGet("{id:int}")]
    public async Task<ActionResult<OrderDto>> GetOrder(int id) { }
    
    // GET api/v1/orders/5/items
    [HttpGet("{orderId:int}/items")]
    public async Task<ActionResult<IEnumerable<OrderItemDto>>> GetOrderItems(int orderId) { }
    
    // POST api/v1/orders
    [HttpPost]
    public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request) { }
    
    // PUT api/v1/orders/5
    [HttpPut("{id:int}")]
    public async Task<IActionResult> UpdateOrder(int id, UpdateOrderRequest request) { }
    
    // PATCH api/v1/orders/5
    [HttpPatch("{id:int}")]
    public async Task<IActionResult> PatchOrder(int id, JsonPatchDocument<OrderDto> patch) { }
    
    // DELETE api/v1/orders/5
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> DeleteOrder(int id) { }
    
    // POST api/v1/orders/5/cancel (action on resource)
    [HttpPost("{id:int}/cancel")]
    public async Task<ActionResult<OrderDto>> CancelOrder(int id) { }
}
```

**Why**:
- Clear, predictable URL structure
- HTTP verbs convey the action
- Supports proper caching
- Standard REST conventions
- Better API discoverability

---

### Rule 7: Validate Input with Model Validation

**Priority**: High

**Description**: Always validate incoming data using Data Annotations or FluentValidation.

**Incorrect**:

```csharp
public class CreateOrderRequest
{
    public string CustomerEmail { get; set; }  // No validation
    public List<OrderItemRequest> Items { get; set; }  // Can be null
}

[HttpPost]
public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
{
    // Manual validation - error-prone and verbose
    if (string.IsNullOrEmpty(request.CustomerEmail))
        return BadRequest("Email is required");
    
    if (!request.CustomerEmail.Contains("@"))
        return BadRequest("Invalid email format");
    
    if (request.Items == null || request.Items.Count == 0)
        return BadRequest("At least one item is required");
    
    // ... more manual validation
}
```

**Correct**:

```csharp
public class CreateOrderRequest
{
    [Required(ErrorMessage = "Customer email is required")]
    [EmailAddress(ErrorMessage = "Invalid email format")]
    [MaxLength(256)]
    public required string CustomerEmail { get; init; }

    [Required]
    [MinLength(1, ErrorMessage = "At least one item is required")]
    public required List<OrderItemRequest> Items { get; init; }

    [Range(0, double.MaxValue, ErrorMessage = "Discount must be non-negative")]
    public decimal Discount { get; init; }
}

public class OrderItemRequest
{
    [Required]
    [Range(1, int.MaxValue, ErrorMessage = "Valid product ID is required")]
    public int ProductId { get; init; }

    [Required]
    [Range(1, 1000, ErrorMessage = "Quantity must be between 1 and 1000")]
    public int Quantity { get; init; }
}

// Or use FluentValidation
public class CreateOrderRequestValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderRequestValidator()
    {
        RuleFor(x => x.CustomerEmail)
            .NotEmpty().WithMessage("Customer email is required")
            .EmailAddress().WithMessage("Invalid email format")
            .MaximumLength(256);

        RuleFor(x => x.Items)
            .NotEmpty().WithMessage("At least one item is required");

        RuleForEach(x => x.Items).SetValidator(new OrderItemRequestValidator());
    }
}

// Controller - validation happens automatically
[HttpPost]
public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
{
    // Model validation is automatic with [ApiController]
    // Invalid requests return 400 with ValidationProblemDetails
    var order = await _service.CreateOrderAsync(request);
    return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
}
```

**Why**:
- Declarative and maintainable
- Automatic validation with `[ApiController]`
- Consistent error responses
- Separation of concerns
- Reusable validation rules

---

### Rule 8: Use Async/Await Properly

**Priority**: High

**Description**: Use async operations for I/O-bound work and avoid blocking calls.

**Incorrect**:

```csharp
[HttpGet("{id}")]
public ActionResult<OrderDto> GetOrder(int id)
{
    // Blocking call - ties up thread
    var order = _context.Orders.Find(id);
    return Ok(order);
}

[HttpGet]
public async Task<ActionResult<IEnumerable<OrderDto>>> GetOrders()
{
    // .Result blocks the thread
    var orders = _context.Orders.ToListAsync().Result;
    return Ok(orders);
}

[HttpPost]
public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
{
    // Fire and forget - exception is lost
    _ = _emailService.SendOrderConfirmationAsync(request.CustomerEmail);
    
    var order = await _repository.CreateAsync(request);
    return Ok(order);
}
```

**Correct**:

```csharp
[HttpGet("{id}")]
public async Task<ActionResult<OrderDto>> GetOrder(int id, CancellationToken cancellationToken)
{
    var order = await _context.Orders
        .AsNoTracking()
        .FirstOrDefaultAsync(o => o.Id == id, cancellationToken);
    
    if (order is null)
        return NotFound();
    
    return Ok(_mapper.Map<OrderDto>(order));
}

[HttpGet]
public async Task<ActionResult<IEnumerable<OrderDto>>> GetOrders(CancellationToken cancellationToken)
{
    var orders = await _context.Orders
        .AsNoTracking()
        .ToListAsync(cancellationToken);
    
    return Ok(_mapper.Map<IEnumerable<OrderDto>>(orders));
}

[HttpPost]
public async Task<ActionResult<OrderDto>> CreateOrder(
    CreateOrderRequest request,
    CancellationToken cancellationToken)
{
    var order = await _repository.CreateAsync(request, cancellationToken);
    
    // Use background job for non-critical operations
    _backgroundJobs.Enqueue(() => _emailService.SendOrderConfirmationAsync(order.Id));
    
    return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
}
```

**Why**:
- Non-blocking operations improve scalability
- CancellationToken allows request cancellation
- Proper error handling for async operations
- Better resource utilization

---

## Integration Example

Complete controller following all best practices:

```csharp
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace MyApi.Controllers;

[ApiController]
[Route("api/v1/products")]
[Produces("application/json")]
public class ProductsController : ControllerBase
{
    private readonly AppDbContext _context;
    private readonly IMapper _mapper;
    private readonly ILogger<ProductsController> _logger;

    public ProductsController(
        AppDbContext context,
        IMapper mapper,
        ILogger<ProductsController> logger)
    {
        _context = context;
        _mapper = mapper;
        _logger = logger;
    }

    /// <summary>
    /// Gets a paginated list of products
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResponse<ProductDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<PagedResponse<ProductDto>>> GetProducts(
        [FromQuery] PaginationParams pagination,
        [FromQuery] string? search = null,
        CancellationToken cancellationToken = default)
    {
        var query = _context.Products.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(p => p.Name.Contains(search));
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var totalPages = (int)Math.Ceiling(totalCount / (double)pagination.PageSize);

        var items = await query
            .OrderBy(p => p.Name)
            .Skip((pagination.PageNumber - 1) * pagination.PageSize)
            .Take(pagination.PageSize)
            .Select(p => _mapper.Map<ProductDto>(p))
            .ToListAsync(cancellationToken);

        return Ok(new PagedResponse<ProductDto>(
            items, pagination.PageNumber, pagination.PageSize, totalCount, totalPages));
    }

    /// <summary>
    /// Gets a product by ID
    /// </summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType(typeof(ProductDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProductDto>> GetProduct(
        int id,
        CancellationToken cancellationToken)
    {
        var product = await _context.Products
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == id, cancellationToken);

        if (product is null)
        {
            _logger.LogWarning("Product {ProductId} not found", id);
            return NotFound();
        }

        return Ok(_mapper.Map<ProductDto>(product));
    }

    /// <summary>
    /// Creates a new product
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(ProductDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<ProductDto>> CreateProduct(
        CreateProductRequest request,
        CancellationToken cancellationToken)
    {
        var product = _mapper.Map<Product>(request);
        
        _context.Products.Add(product);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation("Created product {ProductId}", product.Id);

        var dto = _mapper.Map<ProductDto>(product);
        return CreatedAtAction(nameof(GetProduct), new { id = product.Id }, dto);
    }

    /// <summary>
    /// Updates an existing product
    /// </summary>
    [HttpPut("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> UpdateProduct(
        int id,
        UpdateProductRequest request,
        CancellationToken cancellationToken)
    {
        var product = await _context.Products.FindAsync(new object[] { id }, cancellationToken);

        if (product is null)
            return NotFound();

        _mapper.Map(request, product);
        await _context.SaveChangesAsync(cancellationToken);

        return NoContent();
    }

    /// <summary>
    /// Deletes a product
    /// </summary>
    [HttpDelete("{id:int}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteProduct(int id, CancellationToken cancellationToken)
    {
        var product = await _context.Products.FindAsync(new object[] { id }, cancellationToken);

        if (product is null)
            return NotFound();

        _context.Products.Remove(product);
        await _context.SaveChangesAsync(cancellationToken);

        _logger.LogInformation("Deleted product {ProductId}", id);

        return NoContent();
    }
}
```

## Checklist

Use this checklist when reviewing API code:

- [ ] Correct HTTP status codes for all scenarios
- [ ] DTOs used instead of domain entities
- [ ] `ActionResult<T>` with `[ProducesResponseType]` attributes
- [ ] Global exception handling with ProblemDetails
- [ ] Pagination for list endpoints
- [ ] RESTful route design (no verbs in URLs)
- [ ] Input validation with Data Annotations or FluentValidation
- [ ] Async/await with CancellationToken
- [ ] Proper logging with structured parameters
- [ ] API versioning strategy

## References

- [Microsoft REST API Guidelines](https://github.com/microsoft/api-guidelines)
- [ASP.NET Core Web API Documentation](https://docs.microsoft.com/aspnet/core/web-api/)
- [ProblemDetails RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807)
- [HTTP Status Codes](https://httpstatuses.com/)

## Changelog

### v1.0.0
- Initial release
- 8 core rules for Web API development
