---
name: error-handling-patterns
description: Best practices for implementing comprehensive error handling in ASP.NET Core including global exception handlers, exception filters, ProblemDetails format, and error correlation.
version: 1.0.0
priority: critical
categories:
  - api
  - error-handling
  - patterns
use_when:
  - "When implementing global exception handling"
  - "When designing error response format"
  - "When handling unhandled exceptions"
  - "When implementing error logging and correlation"
  - "When creating custom exception types"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.AspNetCore.Mvc"
related_skills:
  - webapi-best-practices
  - structured-logging
  - owasp-api-security
---

# Error Handling Patterns

## Overview

This skill covers comprehensive error handling strategies in ASP.NET Core. Proper error handling is critical for API reliability, security, and developer experience. This skill addresses:

- Global exception handling middleware
- Exception filters
- ProblemDetails format (RFC 7807)
- Custom exception types
- Error logging and correlation
- Security considerations

## Rules

### Rule 1: Implement Global Exception Handler

**Priority**: Critical

**Description**: Use a global exception handler middleware to catch all unhandled exceptions and return consistent error responses.

**Incorrect**:

```csharp
// No global exception handling
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
        // Inconsistent error handling
        return BadRequest(new { error = ex.Message });
    }
}

// Exceptions bubble up to framework - exposes stack traces
public async Task<IActionResult> ProcessOrder(int id)
{
    var order = await _service.ProcessAsync(id); // Exception not caught
    return Ok(order);
}
```

**Correct**:

```csharp
// Global Exception Handler
public class GlobalExceptionHandler : IExceptionHandler
{
    private readonly ILogger<GlobalExceptionHandler> _logger;
    private readonly IHostEnvironment _environment;

    public GlobalExceptionHandler(
        ILogger<GlobalExceptionHandler> logger,
        IHostEnvironment environment)
    {
        _logger = logger;
        _environment = environment;
    }

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        _logger.LogError(
            exception,
            "Unhandled exception occurred. TraceId: {TraceId}",
            httpContext.TraceIdentifier);

        var problemDetails = CreateProblemDetails(httpContext, exception);
        
        httpContext.Response.StatusCode = problemDetails.Status ?? 500;
        httpContext.Response.ContentType = "application/problem+json";
        
        await httpContext.Response.WriteAsJsonAsync(problemDetails, cancellationToken);
        return true;
    }

    private ProblemDetails CreateProblemDetails(HttpContext context, Exception exception)
    {
        return exception switch
        {
            NotFoundException notFound => new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Type = "https://tools.ietf.org/html/rfc7231#section-6.5.4",
                Title = "Resource not found",
                Detail = notFound.Message,
                Instance = context.Request.Path,
                Extensions = { ["traceId"] = context.TraceIdentifier }
            },
            ValidationException validation => new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Type = "https://tools.ietf.org/html/rfc7231#section-6.5.1",
                Title = "Validation failed",
                Detail = validation.Message,
                Instance = context.Request.Path,
                Extensions =
                {
                    ["traceId"] = context.TraceIdentifier,
                    ["errors"] = validation.Errors
                }
            },
            UnauthorizedException unauthorized => new ProblemDetails
            {
                Status = StatusCodes.Status401Unauthorized,
                Type = "https://tools.ietf.org/html/rfc7235#section-3.1",
                Title = "Unauthorized",
                Detail = unauthorized.Message,
                Instance = context.Request.Path,
                Extensions = { ["traceId"] = context.TraceIdentifier }
            },
            ForbiddenException forbidden => new ProblemDetails
            {
                Status = StatusCodes.Status403Forbidden,
                Type = "https://tools.ietf.org/html/rfc7231#section-6.5.3",
                Title = "Forbidden",
                Detail = forbidden.Message,
                Instance = context.Request.Path,
                Extensions = { ["traceId"] = context.TraceIdentifier }
            },
            ConflictException conflict => new ProblemDetails
            {
                Status = StatusCodes.Status409Conflict,
                Type = "https://tools.ietf.org/html/rfc7231#section-6.5.8",
                Title = "Conflict",
                Detail = conflict.Message,
                Instance = context.Request.Path,
                Extensions = { ["traceId"] = context.TraceIdentifier }
            },
            _ => new ProblemDetails
            {
                Status = StatusCodes.Status500InternalServerError,
                Type = "https://tools.ietf.org/html/rfc7231#section-6.6.1",
                Title = "An error occurred",
                Detail = _environment.IsDevelopment() 
                    ? exception.Message 
                    : "An unexpected error occurred. Please try again later.",
                Instance = context.Request.Path,
                Extensions =
                {
                    ["traceId"] = context.TraceIdentifier
                }
            }
        };
    }
}

// Register in Program.cs
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

var app = builder.Build();
app.UseExceptionHandler();
app.Run();
```

**Why**:
- Consistent error format across all endpoints
- No sensitive information leaked (stack traces only in development)
- RFC 7807 compliant (ProblemDetails)
- Centralized error logging
- Better client experience

---

### Rule 2: Use ProblemDetails Format

**Priority**: Critical

**Description**: Always return errors in ProblemDetails format (RFC 7807) for consistency and standards compliance.

**Incorrect**:

```csharp
// Inconsistent error formats
[HttpPost("orders")]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    if (request.Items.Count == 0)
        return BadRequest(new { message = "Items required" }); // Custom format
    
    if (request.CustomerId <= 0)
        return BadRequest("Invalid customer ID"); // String response
    
    try
    {
        var order = await _service.CreateAsync(request);
        return Ok(order);
    }
    catch (Exception ex)
    {
        return StatusCode(500, new { error = ex.Message, stackTrace = ex.StackTrace }); // Exposes stack trace
    }
}
```

**Correct**:

```csharp
// Consistent ProblemDetails format
[HttpPost("orders")]
[ProducesResponseType(typeof(OrderDto), StatusCodes.Status201Created)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status500InternalServerError)]
public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
{
    // Validation handled by [ApiController] - returns ValidationProblemDetails automatically
    
    try
    {
        var order = await _service.CreateAsync(request);
        return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
    }
    catch (NotFoundException ex)
    {
        return Problem(
            title: "Resource not found",
            detail: ex.Message,
            statusCode: StatusCodes.Status404NotFound);
    }
    catch (ValidationException ex)
    {
        return ValidationProblem(new Dictionary<string, string[]>
        {
            { "Items", new[] { ex.Message } }
        });
    }
    // Other exceptions handled by global handler
}

// Or use custom ProblemDetails
[HttpPost("orders")]
public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
{
    if (request.Items.Count == 0)
    {
        return Problem(
            title: "Validation failed",
            detail: "At least one item is required",
            statusCode: StatusCodes.Status400BadRequest,
            instance: Request.Path,
            extensions: new Dictionary<string, object>
            {
                ["errors"] = new { Items = new[] { "At least one item is required" } }
            });
    }
    
    var order = await _service.CreateAsync(request);
    return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
}
```

**Why**:
- RFC 7807 standard format
- Consistent across all errors
- Machine-readable error details
- Better API documentation
- Client-friendly format

---

### Rule 3: Create Custom Exception Types

**Priority**: High

**Description**: Create domain-specific exception types instead of using generic Exception.

**Incorrect**:

```csharp
// Using generic exceptions
public async Task<Order> GetOrderAsync(int id)
{
    var order = await _repository.GetByIdAsync(id);
    if (order == null)
        throw new Exception("Order not found"); // Too generic
    
    if (order.Status == OrderStatus.Cancelled)
        throw new Exception("Cannot process cancelled order"); // No context
}

// Catching generic Exception
try
{
    await ProcessOrderAsync(id);
}
catch (Exception ex) // Too broad
{
    // Can't differentiate between error types
    return BadRequest(ex.Message);
}
```

**Correct**:

```csharp
// Custom exception hierarchy
public abstract class AppException : Exception
{
    public int StatusCode { get; }
    public string ErrorCode { get; }

    protected AppException(
        string message,
        int statusCode,
        string errorCode,
        Exception? innerException = null)
        : base(message, innerException)
    {
        StatusCode = statusCode;
        ErrorCode = errorCode;
    }
}

public class NotFoundException : AppException
{
    public NotFoundException(string resourceName, object? resourceId = null)
        : base(
            $"Resource '{resourceName}'{(resourceId != null ? $" with ID '{resourceId}'" : "")} was not found.",
            StatusCodes.Status404NotFound,
            "RESOURCE_NOT_FOUND")
    {
    }
}

public class ValidationException : AppException
{
    public Dictionary<string, string[]> Errors { get; }

    public ValidationException(string message, Dictionary<string, string[]>? errors = null)
        : base(message, StatusCodes.Status400BadRequest, "VALIDATION_FAILED")
    {
        Errors = errors ?? new Dictionary<string, string[]>();
    }
}

public class UnauthorizedException : AppException
{
    public UnauthorizedException(string message = "Authentication required")
        : base(message, StatusCodes.Status401Unauthorized, "UNAUTHORIZED")
    {
    }
}

public class ForbiddenException : AppException
{
    public ForbiddenException(string message = "Insufficient permissions")
        : base(message, StatusCodes.Status403Forbidden, "FORBIDDEN")
    {
    }
}

public class ConflictException : AppException
{
    public ConflictException(string message)
        : base(message, StatusCodes.Status409Conflict, "CONFLICT")
    {
    }
}

// Usage in services
public async Task<Order> GetOrderAsync(int id)
{
    var order = await _repository.GetByIdAsync(id);
    if (order == null)
        throw new NotFoundException("Order", id);
    
    if (order.Status == OrderStatus.Cancelled)
        throw new ConflictException("Cannot process cancelled order");
    
    return order;
}

// Specific exception handling
try
{
    await ProcessOrderAsync(id);
}
catch (NotFoundException ex)
{
    return NotFound(ex.Message);
}
catch (ConflictException ex)
{
    return Conflict(ex.Message);
}
catch (ValidationException ex)
{
    return ValidationProblem(ex.Errors);
}
```

**Why**:
- Clear error semantics
- Type-safe error handling
- Better error categorization
- Easier to handle specific errors
- Domain-specific error messages

---

### Rule 4: Log Errors with Context

**Priority**: Critical

**Description**: Always log exceptions with sufficient context for debugging, including correlation IDs and request details.

**Incorrect**:

```csharp
// Minimal logging
try
{
    await ProcessOrderAsync(id);
}
catch (Exception ex)
{
    _logger.LogError(ex, "Error occurred"); // No context
    throw;
}

// Logging sensitive data
_logger.LogError(ex, "Error processing order for user {Email} with password {Password}", 
    user.Email, user.Password); // Never log passwords!
```

**Correct**:

```csharp
// Comprehensive error logging
public class OrderService
{
    private readonly ILogger<OrderService> _logger;

    public async Task<Order> ProcessOrderAsync(int orderId)
    {
        using var activity = ActivitySource.StartActivity("ProcessOrder");
        activity?.SetTag("order.id", orderId);

        try
        {
            _logger.LogInformation(
                "Processing order {OrderId}",
                orderId);

            var order = await _repository.GetByIdAsync(orderId);
            if (order == null)
            {
                _logger.LogWarning(
                    "Order {OrderId} not found",
                    orderId);
                throw new NotFoundException("Order", orderId);
            }

            // Process order...
            return order;
        }
        catch (NotFoundException)
        {
            // Re-throw - don't log as error
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Failed to process order {OrderId}. User: {UserId}, Status: {OrderStatus}",
                orderId,
                order?.UserId,
                order?.Status);

            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.RecordException(ex);

            throw;
        }
    }
}

// Global handler with correlation
public class GlobalExceptionHandler : IExceptionHandler
{
    private readonly ILogger<GlobalExceptionHandler> _logger;

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        var traceId = httpContext.TraceIdentifier;
        var userId = httpContext.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "anonymous";
        var path = httpContext.Request.Path;
        var method = httpContext.Request.Method;

        _logger.LogError(
            exception,
            "Unhandled exception. TraceId: {TraceId}, UserId: {UserId}, Path: {Path}, Method: {Method}",
            traceId,
            userId,
            path,
            method);

        // Create ProblemDetails with traceId
        var problemDetails = new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "An error occurred",
            Detail = "An unexpected error occurred. Please try again later.",
            Instance = path,
            Extensions = { ["traceId"] = traceId }
        };

        httpContext.Response.StatusCode = problemDetails.Status ?? 500;
        await httpContext.Response.WriteAsJsonAsync(problemDetails, cancellationToken);
        return true;
    }
}
```

**Why**:
- Enables debugging production issues
- Correlation IDs link logs to requests
- Context helps identify root causes
- Essential for distributed systems
- Security: never log sensitive data

---

### Rule 5: Handle Validation Errors Consistently

**Priority**: High

**Description**: Use consistent validation error format with detailed field-level errors.

**Incorrect**:

```csharp
// Inconsistent validation
[HttpPost("orders")]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    if (string.IsNullOrEmpty(request.CustomerEmail))
        return BadRequest("Email is required");
    
    if (!request.CustomerEmail.Contains("@"))
        return BadRequest("Invalid email");
    
    if (request.Items == null || request.Items.Count == 0)
        return BadRequest("Items required");
    
    // Different error format for each validation
}
```

**Correct**:

```csharp
// Using FluentValidation for consistent validation
public class CreateOrderRequestValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderRequestValidator()
    {
        RuleFor(x => x.CustomerEmail)
            .NotEmpty().WithMessage("Email is required")
            .EmailAddress().WithMessage("Invalid email format");

        RuleFor(x => x.Items)
            .NotEmpty().WithMessage("At least one item is required")
            .Must(items => items.All(i => i.Quantity > 0))
            .WithMessage("All items must have quantity greater than 0");

        RuleForEach(x => x.Items)
            .SetValidator(new OrderItemRequestValidator());
    }
}

// Register validators
builder.Services.AddControllers();
builder.Services.AddFluentValidationAutoValidation();

// Controller - validation automatic
[HttpPost("orders")]
[ProducesResponseType(typeof(OrderDto), StatusCodes.Status201Created)]
[ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
public async Task<ActionResult<OrderDto>> CreateOrder([FromBody] CreateOrderRequest request)
{
    // Validation happens automatically, returns ValidationProblemDetails
    var order = await _service.CreateAsync(request);
    return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
}

// ValidationProblemDetails format:
// {
//   "type": "https://tools.ietf.org/html/rfc7231#section-6.5.1",
//   "title": "One or more validation errors occurred",
//   "status": 400,
//   "errors": {
//     "CustomerEmail": ["Email is required", "Invalid email format"],
//     "Items": ["At least one item is required"]
//   }
// }
```

**Why**:
- Consistent validation error format
- Field-level error details
- Automatic with [ApiController]
- Better client experience
- Standards-compliant

---

### Rule 6: Never Expose Stack Traces in Production

**Priority**: Critical

**Description**: Never return stack traces or internal exception details to clients in production.

**Incorrect**:

```csharp
// Exposing stack traces
catch (Exception ex)
{
    return StatusCode(500, new
    {
        message = ex.Message,
        stackTrace = ex.StackTrace, // Security risk!
        innerException = ex.InnerException?.Message,
        source = ex.Source
    });
}

// Logging and returning exception details
_logger.LogError(ex, "Error: {Exception}", ex.ToString()); // Includes stack trace
return Problem(detail: ex.ToString()); // Exposes everything
```

**Correct**:

```csharp
// Safe error handling
public class GlobalExceptionHandler : IExceptionHandler
{
    private readonly IHostEnvironment _environment;

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        // Log full exception (including stack trace) - safe in logs
        _logger.LogError(
            exception,
            "Unhandled exception. TraceId: {TraceId}",
            httpContext.TraceIdentifier);

        // Return safe error to client
        var problemDetails = new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "An error occurred",
            Detail = _environment.IsDevelopment()
                ? exception.Message // Only in development
                : "An unexpected error occurred. Please try again later.",
            Instance = httpContext.Request.Path,
            Extensions = { ["traceId"] = httpContext.TraceIdentifier }
        };

        // Never include stack trace in response
        httpContext.Response.StatusCode = problemDetails.Status ?? 500;
        await httpContext.Response.WriteAsJsonAsync(problemDetails, cancellationToken);
        return true;
    }
}

// Or use ProblemDetails factory
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        var exception = context.HttpContext.Features.Get<IExceptionHandlerFeature>()?.Error;
        
        if (exception != null && !context.HttpContext.RequestServices
            .GetRequiredService<IHostEnvironment>().IsDevelopment())
        {
            // Hide exception details in production
            context.ProblemDetails.Detail = "An unexpected error occurred.";
        }
    };
});
```

**Why**:
- Prevents information disclosure
- Security best practice
- Protects internal implementation
- OWASP compliance
- Professional error handling

---

### Rule 7: Use Exception Filters for Specific Scenarios

**Priority**: Medium

**Description**: Use exception filters for controller-specific or action-specific error handling.

**Incorrect**:

```csharp
// Try-catch in every action
[HttpPost("orders")]
public async Task<IActionResult> CreateOrder(CreateOrderRequest request)
{
    try
    {
        var order = await _service.CreateAsync(request);
        return Ok(order);
    }
    catch (NotFoundException ex)
    {
        return NotFound(ex.Message);
    }
    catch (ValidationException ex)
    {
        return BadRequest(ex.Message);
    }
    // Repeated in every action
}
```

**Correct**:

```csharp
// Exception filter
public class ApiExceptionFilter : IExceptionFilter
{
    private readonly ILogger<ApiExceptionFilter> _logger;
    private readonly IHostEnvironment _environment;

    public void OnException(ExceptionContext context)
    {
        var exception = context.Exception;
        var problemDetails = exception switch
        {
            NotFoundException notFound => new ProblemDetails
            {
                Status = StatusCodes.Status404NotFound,
                Title = "Resource not found",
                Detail = notFound.Message
            },
            ValidationException validation => new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Validation failed",
                Detail = validation.Message,
                Extensions = { ["errors"] = validation.Errors }
            },
            _ => null
        };

        if (problemDetails != null)
        {
            context.Result = new ObjectResult(problemDetails)
            {
                StatusCode = problemDetails.Status
            };
            context.ExceptionHandled = true;
        }
    }
}

// Apply globally or per controller
builder.Services.AddControllers(options =>
{
    options.Filters.Add<ApiExceptionFilter>();
});

// Or per controller
[ApiController]
[TypeFilter(typeof(ApiExceptionFilter))]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    // Exceptions handled by filter
    [HttpPost]
    public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
    {
        var order = await _service.CreateAsync(request);
        return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
    }
}
```

**Why**:
- DRY - don't repeat error handling
- Controller-specific handling
- Can combine with global handler
- Flexible error handling
- Cleaner controller code

---

## Integration Example

Complete error handling setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddProblemDetails();

// Custom exception handler
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddExceptionHandler(options =>
{
    options.ExceptionHandler = async context =>
    {
        var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        
        logger.LogError(exception, "Unhandled exception");
        
        var problemDetails = new ProblemDetails
        {
            Status = StatusCodes.Status500InternalServerError,
            Title = "An error occurred",
            Detail = builder.Environment.IsDevelopment() 
                ? exception?.Message 
                : "An unexpected error occurred"
        };
        
        context.Response.StatusCode = problemDetails.Status ?? 500;
        await context.Response.WriteAsJsonAsync(problemDetails);
    };
});

// Exception filter
builder.Services.AddControllers(options =>
{
    options.Filters.Add<ApiExceptionFilter>();
});

var app = builder.Build();

app.UseExceptionHandler();
app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] Global exception handler implemented
- [ ] ProblemDetails format used consistently
- [ ] Custom exception types created
- [ ] Errors logged with context and correlation IDs
- [ ] Validation errors handled consistently
- [ ] Stack traces never exposed in production
- [ ] Exception filters used where appropriate
- [ ] Error responses are RFC 7807 compliant

## References

- [Error Handling](https://docs.microsoft.com/aspnet/core/fundamentals/error-handling)
- [ProblemDetails RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807)
- [Exception Handling Middleware](https://docs.microsoft.com/aspnet/core/fundamentals/error-handling#exception-handler-middleware)

## Changelog

### v1.0.0
- Initial release
- 7 core rules for error handling
