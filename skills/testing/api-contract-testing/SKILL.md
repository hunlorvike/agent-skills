---
name: api-contract-testing
description: Best practices for API contract testing in ASP.NET Core to ensure API contracts remain stable and compatible across versions using OpenAPI validation and contract testing tools.
version: 1.0.0
priority: medium
categories:
  - testing
  - api
  - contracts
use_when:
  - "When maintaining API compatibility"
  - "When preventing breaking changes"
  - "When validating OpenAPI specifications"
  - "When testing API contracts"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Swashbuckle.AspNetCore"
related_skills:
  - webapi-best-practices
  - openapi-swagger
  - integration-testing
---

# API Contract Testing Best Practices

## Overview

This skill covers API contract testing to ensure API contracts remain stable and prevent breaking changes that could break client applications.

## Rules

### Rule 1: Validate OpenAPI Schema

**Priority**: High

**Description**: Validate that the generated OpenAPI schema matches expected contracts.

**Incorrect**:

```csharp
// No contract validation
[HttpPost("products")]
public async Task<IActionResult> CreateProduct([FromBody] CreateProductRequest request)
{
    // Changing request structure breaks clients
    var product = await _service.CreateAsync(request);
    return Ok(product);
}
```

**Correct**:

```csharp
// Contract test
[Fact]
public async Task CreateProduct_MatchesOpenApiSchema()
{
    // Arrange
    var factory = new WebApplicationFactory<Program>();
    var client = factory.CreateClient();

    // Act
    var response = await client.GetAsync("/swagger/v1/swagger.json");
    var swaggerJson = await response.Content.ReadAsStringAsync();
    var swagger = JsonSerializer.Deserialize<OpenApiDocument>(swaggerJson);

    // Assert
    Assert.NotNull(swagger);
    var createProductPath = swagger.Paths["/api/products"];
    Assert.NotNull(createProductPath);
    
    var postOperation = createProductPath.Operations[OperationType.Post];
    Assert.NotNull(postOperation);
    
    // Validate request schema
    var requestBody = postOperation.RequestBody;
    Assert.NotNull(requestBody);
    
    // Validate response schema
    var response200 = postOperation.Responses["200"];
    Assert.NotNull(response200);
}

// Or use dedicated contract testing library
// Install: PactNet

[Fact]
public async Task ProductsApi_ShouldHonorContract()
{
    // Arrange
    var pact = new PactBuilder()
        .ServiceConsumer("ProductConsumer")
        .HasPactWith("ProductAPI")
        .Build();

    // Act & Assert
    pact.UponReceiving("a request to create a product")
        .Given("a valid product request")
        .WithRequest(HttpMethod.Post, "/api/products")
        .WithHeader("Content-Type", "application/json")
        .WithJsonBody(new
        {
            name = "Test Product",
            price = 10.00m
        })
        .WillRespondWith(StatusCodes.Status201Created)
        .WithJsonBody(new
        {
            id = 1,
            name = "Test Product",
            price = 10.00m
        });

    await pact.ExecuteAsync(async ctx =>
    {
        var client = new HttpClient { BaseAddress = ctx.MockServerUri };
        var response = await client.PostAsJsonAsync("/api/products", new
        {
            name = "Test Product",
            price = 10.00m
        });
        
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    });
}
```

**Why**:
- Prevents breaking changes
- Ensures API compatibility
- Validates OpenAPI accuracy
- Protects client applications

---

### Rule 2: Test Request/Response Contracts

**Priority**: High

**Description**: Validate that request and response DTOs match the contract.

**Correct**:

```csharp
[Fact]
public async Task CreateProductRequest_MatchesContract()
{
    // Arrange
    var request = new CreateProductRequest
    {
        Name = "Test Product",
        Price = 10.00m,
        Sku = "TEST-001"
    };

    // Act
    var json = JsonSerializer.Serialize(request);
    var deserialized = JsonSerializer.Deserialize<CreateProductRequest>(json);

    // Assert
    Assert.NotNull(deserialized);
    Assert.Equal(request.Name, deserialized.Name);
    Assert.Equal(request.Price, deserialized.Price);
    Assert.Equal(request.Sku, deserialized.Sku);
}

[Fact]
public async Task ProductDto_MatchesContract()
{
    // Arrange
    var dto = new ProductDto(
        Id: 1,
        Name: "Test Product",
        Description: "Test Description",
        Price: 10.00m,
        Sku: "TEST-001",
        StockQuantity: 100,
        IsActive: true
    );

    // Act
    var json = JsonSerializer.Serialize(dto);
    var schema = JsonSchema.FromType<ProductDto>();

    // Assert - validate against schema
    var validation = schema.Validate(json);
    Assert.True(validation.IsValid);
}
```

**Why**:
- Ensures DTOs match contracts
- Validates serialization
- Prevents schema drift
- Better compatibility

---

### Rule 3: Version Contract Compatibility

**Priority**: Medium

**Description**: Test that API versions maintain backward compatibility.

**Correct**:

```csharp
[Fact]
public async Task ApiV2_BackwardCompatibleWithV1()
{
    // Arrange
    var factory = new WebApplicationFactory<Program>();
    var v1Client = factory.CreateClient();
    var v2Client = factory.CreateClient();

    // Act - V1 request
    var v1Response = await v1Client.GetAsync("/api/v1/products/1");
    var v1Product = await v1Response.Content.ReadFromJsonAsync<Product>();

    // Act - V2 request
    var v2Response = await v2Client.GetAsync("/api/v2/products/1");
    var v2Product = await v2Response.Content.ReadFromJsonAsync<ProductDto>();

    // Assert - V2 should contain all V1 fields
    Assert.Equal(v1Product.Id, v2Product.Id);
    Assert.Equal(v1Product.Name, v2Product.Name);
    Assert.Equal(v1Product.Price, v2Product.Price);
}

[Fact]
public async Task BreakingChange_Detected()
{
    // This test should fail if breaking changes are introduced
    var factory = new WebApplicationFactory<Program>();
    var client = factory.CreateClient();

    // Old client expecting old response format
    var response = await client.GetAsync("/api/v2/products/1");
    var product = await response.Content.ReadFromJsonAsync<OldProductFormat>();

    // If this fails, it's a breaking change
    Assert.NotNull(product);
}
```

**Why**:
- Ensures version compatibility
- Detects breaking changes
- Protects existing clients
- Better versioning strategy

---

## Integration Example

Complete contract testing setup:

```csharp
public class ApiContractTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public ApiContractTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Swagger_MatchesApiImplementation()
    {
        var client = _factory.CreateClient();
        var response = await client.GetAsync("/swagger/v1/swagger.json");
        var swagger = await response.Content.ReadFromJsonAsync<OpenApiDocument>();
        
        Assert.NotNull(swagger);
        // Validate contract
    }
}
```

## Checklist

- [ ] OpenAPI schema validated
- [ ] Request contracts tested
- [ ] Response contracts tested
- [ ] Version compatibility verified
- [ ] Breaking changes detected
- [ ] Contract tests in CI/CD

## References

- [API Versioning](https://docs.microsoft.com/aspnet/core/web-api/versioning)
- [Pact Contract Testing](https://docs.pact.io/)

## Changelog

### v1.0.0
- Initial release
- 3 core rules for API contract testing
