---
name: input-validation
description: Best practices for validating input in ASP.NET Core APIs using Data Annotations, FluentValidation, and custom validators to prevent invalid data and security issues.
version: 1.0.0
priority: high
categories:
  - security
  - validation
  - api
use_when:
  - "When accepting user input"
  - "When implementing API endpoints"
  - "When preventing injection attacks"
  - "When ensuring data integrity"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "FluentValidation.AspNetCore (optional)"
related_skills:
  - webapi-best-practices
  - owasp-api-security
---

# Input Validation Best Practices

## Overview

This skill covers comprehensive input validation strategies in ASP.NET Core. Proper validation prevents security vulnerabilities and ensures data integrity.

## Rules

### Rule 1: Validate All Input

**Priority**: Critical

**Description**: Never trust user input. Validate all data from clients.

**Incorrect**:

```csharp
// No validation
[HttpPost("products")]
public async Task<IActionResult> CreateProduct([FromBody] CreateProductRequest request)
{
    var product = new Product
    {
        Name = request.Name, // Could be null, empty, or malicious
        Price = request.Price // Could be negative or extremely large
    };
    _context.Products.Add(product);
    await _context.SaveChangesAsync();
    return Ok(product);
}
```

**Correct**:

```csharp
// Using Data Annotations
public record CreateProductRequest
{
    [Required(ErrorMessage = "Product name is required")]
    [StringLength(200, MinimumLength = 3, ErrorMessage = "Name must be between 3 and 200 characters")]
    public required string Name { get; init; }

    [Required]
    [Range(0.01, 999999.99, ErrorMessage = "Price must be between 0.01 and 999999.99")]
    public decimal Price { get; init; }

    [StringLength(2000)]
    public string? Description { get; init; }

    [Required]
    [RegularExpression(@"^[A-Z0-9-]+$", ErrorMessage = "SKU must contain only uppercase letters, numbers, and hyphens")]
    public required string Sku { get; init; }
}

[HttpPost("products")]
[ProducesResponseType(typeof(ProductDto), StatusCodes.Status201Created)]
[ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
public async Task<ActionResult<ProductDto>> CreateProduct([FromBody] CreateProductRequest request)
{
    // Validation happens automatically with [ApiController]
    var product = await _service.CreateAsync(request);
    return CreatedAtAction(nameof(GetProduct), new { id = product.Id }, product);
}
```

**Why**:
- Prevents invalid data in database
- Protects against injection attacks
- Ensures data integrity
- Better error messages for clients

---

### Rule 2: Use FluentValidation for Complex Rules

**Priority**: High

**Description**: Use FluentValidation for complex validation logic that Data Annotations can't handle.

**Incorrect**:

```csharp
// Complex validation in controller
[HttpPost("orders")]
public async Task<IActionResult> CreateOrder([FromBody] CreateOrderRequest request)
{
    // Manual validation - error-prone
    if (request.Items == null || request.Items.Count == 0)
        return BadRequest("At least one item is required");
    
    if (request.Items.Any(i => i.Quantity <= 0))
        return BadRequest("All items must have positive quantity");
    
    if (request.DiscountPercent < 0 || request.DiscountPercent > 100)
        return BadRequest("Discount must be between 0 and 100");
    
    // Business rule validation
    var total = request.Items.Sum(i => i.Price * i.Quantity);
    if (request.DiscountPercent > 0 && total < 100)
        return BadRequest("Discount only available for orders over $100");
    
    // ... more validation
}
```

**Correct**:

```csharp
// FluentValidation validator
public class CreateOrderRequestValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderRequestValidator()
    {
        RuleFor(x => x.CustomerId)
            .GreaterThan(0)
            .WithMessage("Customer ID is required");

        RuleFor(x => x.Items)
            .NotEmpty()
            .WithMessage("At least one item is required")
            .Must(items => items.Count <= 50)
            .WithMessage("Maximum 50 items per order");

        RuleForEach(x => x.Items)
            .SetValidator(new OrderItemRequestValidator());

        RuleFor(x => x.DiscountPercent)
            .InclusiveBetween(0, 100)
            .WithMessage("Discount must be between 0 and 100");

        // Cross-property validation
        RuleFor(x => x)
            .Must(x => x.DiscountPercent == 0 || x.Items.Sum(i => i.Price * i.Quantity) >= 100)
            .WithMessage("Discount only available for orders over $100")
            .OverridePropertyName("DiscountPercent");
    }
}

public class OrderItemRequestValidator : AbstractValidator<OrderItemRequest>
{
    public OrderItemRequestValidator()
    {
        RuleFor(x => x.ProductId)
            .GreaterThan(0)
            .WithMessage("Valid product ID is required");

        RuleFor(x => x.Quantity)
            .GreaterThan(0)
            .LessThanOrEqualTo(1000)
            .WithMessage("Quantity must be between 1 and 1000");

        RuleFor(x => x.Price)
            .GreaterThan(0)
            .WithMessage("Price must be positive");
    }
}

// Register validators
builder.Services.AddControllers();
builder.Services.AddFluentValidationAutoValidation();
builder.Services.AddScoped<IValidator<CreateOrderRequest>, CreateOrderRequestValidator>();

// Controller - validation automatic
[HttpPost("orders")]
public async Task<ActionResult<OrderDto>> CreateOrder([FromBody] CreateOrderRequest request)
{
    // Validation happens automatically
    var order = await _service.CreateAsync(request);
    return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
}
```

**Why**:
- Complex validation rules in one place
- Reusable validators
- Better error messages
- Testable validation logic

---

### Rule 3: Sanitize Input to Prevent XSS

**Priority**: Critical

**Description**: Sanitize user input that will be displayed to prevent XSS attacks.

**Incorrect**:

```csharp
// Storing raw HTML - XSS vulnerability
[HttpPost("products")]
public async Task<IActionResult> CreateProduct([FromBody] CreateProductRequest request)
{
    var product = new Product
    {
        Name = request.Name, // Could contain <script>alert('XSS')</script>
        Description = request.Description // HTML injection risk
    };
    _context.Products.Add(product);
    await _context.SaveChangesAsync();
    return Ok(product);
}
```

**Correct**:

```csharp
// Sanitize HTML input
using Ganss.Xss;

builder.Services.AddScoped<IHtmlSanitizer, HtmlSanitizer>(_ =>
{
    var sanitizer = new HtmlSanitizer();
    sanitizer.AllowedTags.Add("p");
    sanitizer.AllowedTags.Add("br");
    sanitizer.AllowedTags.Add("strong");
    sanitizer.AllowedTags.Add("em");
    // Only allow safe HTML tags
    return sanitizer;
});

public class ProductService
{
    private readonly IHtmlSanitizer _sanitizer;

    public ProductService(IHtmlSanitizer sanitizer)
    {
        _sanitizer = sanitizer;
    }

    public async Task<Product> CreateAsync(CreateProductRequest request)
    {
        var product = new Product
        {
            Name = _sanitizer.Sanitize(request.Name), // Remove dangerous HTML
            Description = _sanitizer.Sanitize(request.Description ?? string.Empty)
        };
        // ...
    }
}

// Or use encoding when displaying
public class ProductDto
{
    public string Name { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
}

// In Razor view or API response, encode output
@Html.Raw(Model.Description) // Only if you trust the source
// Or
@Model.Description // Automatically encoded
```

**Why**:
- Prevents XSS attacks
- Protects users from malicious scripts
- Essential for user-generated content
- Security best practice

---

### Rule 4: Validate File Uploads

**Priority**: High

**Description**: Strictly validate file uploads for type, size, and content.

**Incorrect**:

```csharp
// No file validation
[HttpPost("upload")]
public async Task<IActionResult> UploadFile(IFormFile file)
{
    var path = Path.Combine("uploads", file.FileName);
    using var stream = new FileStream(path, FileMode.Create);
    await file.CopyToAsync(stream);
    return Ok(new { path });
}
```

**Correct**:

```csharp
// File validation
public class FileUploadValidator
{
    private static readonly string[] AllowedExtensions = { ".jpg", ".jpeg", ".png", ".pdf" };
    private const long MaxFileSize = 10 * 1024 * 1024; // 10 MB

    public static ValidationResult Validate(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return ValidationResult.Failure("File is required");

        if (file.Length > MaxFileSize)
            return ValidationResult.Failure($"File size exceeds {MaxFileSize / 1024 / 1024} MB");

        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!AllowedExtensions.Contains(extension))
            return ValidationResult.Failure($"File type {extension} is not allowed");

        // Validate content type
        var allowedContentTypes = new[] { "image/jpeg", "image/png", "application/pdf" };
        if (!allowedContentTypes.Contains(file.ContentType))
            return ValidationResult.Failure($"Content type {file.ContentType} is not allowed");

        // Additional: Validate file signature (magic bytes)
        if (!ValidateFileSignature(file))
            return ValidationResult.Failure("File signature does not match extension");

        return ValidationResult.Success();
    }

    private static bool ValidateFileSignature(IFormFile file)
    {
        // Read first bytes to verify file type
        using var stream = file.OpenReadStream();
        var buffer = new byte[4];
        stream.Read(buffer, 0, 4);
        
        // JPEG signature: FF D8 FF
        // PNG signature: 89 50 4E 47
        // PDF signature: 25 50 44 46
        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        return extension switch
        {
            ".jpg" or ".jpeg" => buffer[0] == 0xFF && buffer[1] == 0xD8,
            ".png" => buffer[0] == 0x89 && buffer[1] == 0x50,
            ".pdf" => buffer[0] == 0x25 && buffer[1] == 0x50,
            _ => false
        };
    }
}

[HttpPost("upload")]
[RequestSizeLimit(10 * 1024 * 1024)] // 10 MB
public async Task<IActionResult> UploadFile(IFormFile file)
{
    var validation = FileUploadValidator.Validate(file);
    if (!validation.IsValid)
        return BadRequest(new { errors = validation.Errors });

    // Generate safe filename
    var safeFileName = $"{Guid.NewGuid()}{Path.GetExtension(file.FileName)}";
    var path = Path.Combine("uploads", safeFileName);

    using var stream = new FileStream(path, FileMode.Create);
    await file.CopyToAsync(stream);

    return Ok(new { path, fileName = safeFileName });
}
```

**Why**:
- Prevents malicious file uploads
- Protects against path traversal
- Limits storage usage
- Validates actual file content

---

## Integration Example

Complete validation setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

// FluentValidation
builder.Services.AddFluentValidationAutoValidation();
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// HTML Sanitizer
builder.Services.AddScoped<IHtmlSanitizer, HtmlSanitizer>();

var app = builder.Build();

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] All input validated
- [ ] Data Annotations on DTOs
- [ ] FluentValidation for complex rules
- [ ] HTML sanitization for user content
- [ ] File upload validation
- [ ] Custom validators for business rules
- [ ] Validation error messages are clear

## References

- [Model Validation](https://docs.microsoft.com/aspnet/core/mvc/models/validation)
- [FluentValidation](https://docs.fluentvalidation.net/)
- [OWASP Input Validation](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html)

## Changelog

### v1.0.0
- Initial release
- 4 core rules for input validation
