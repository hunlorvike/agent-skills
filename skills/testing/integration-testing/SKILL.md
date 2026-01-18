---
name: integration-testing
description: Best practices for writing integration tests in ASP.NET Core using WebApplicationFactory, TestContainers, and in-memory databases.
version: 1.0.0
priority: high
categories:
  - testing
  - integration
use_when:
  - "When testing API endpoints end-to-end"
  - "When testing database interactions"
  - "When testing authentication flows"
  - "When validating complete request/response cycles"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "xUnit or NUnit"
  - "Microsoft.AspNetCore.Mvc.Testing"
related_skills:
  - unit-testing
  - webapi-best-practices
---

# Integration Testing Best Practices

## Overview

This skill covers writing integration tests for ASP.NET Core applications that test the full request/response pipeline including middleware, routing, and database interactions.

## Rules

### Rule 1: Use WebApplicationFactory

**Priority**: High

**Description**: Use WebApplicationFactory to create test server for integration tests.

**Incorrect**:

```csharp
// Manual test server setup - complex and error-prone
public class ProductsControllerTests
{
    [Fact]
    public async Task GetProducts_ReturnsOk()
    {
        // Manual server setup...
    }
}
```

**Correct**:

```csharp
// Custom WebApplicationFactory
public class WebApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration(config =>
        {
            // Override configuration for testing
            config.AddInMemoryCollection(new Dictionary<string, string>
            {
                ["ConnectionStrings:DefaultConnection"] = "TestConnection",
                ["Jwt:Key"] = "test-key-for-testing-only"
            });
        });

        builder.ConfigureServices(services =>
        {
            // Replace database with in-memory
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            
            if (descriptor != null)
                services.Remove(descriptor);

            services.AddDbContext<AppDbContext>(options =>
            {
                options.UseInMemoryDatabase("TestDb");
            });
        });
    }
}

// Integration test
public class ProductsControllerIntegrationTests : IClassFixture<WebApiFactory>
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;

    public ProductsControllerIntegrationTests(WebApiFactory factory)
    {
        _factory = factory;
        _client = _factory.CreateClient();
    }

    [Fact]
    public async Task GetProducts_ReturnsOk()
    {
        // Act
        var response = await _client.GetAsync("/api/products");

        // Assert
        response.EnsureSuccessStatusCode();
        var content = await response.Content.ReadAsStringAsync();
        var products = JsonSerializer.Deserialize<List<ProductDto>>(content);
        
        Assert.NotNull(products);
    }
}
```

**Why**:
- Tests full request pipeline
- Includes middleware and routing
- Real HTTP requests/responses
- Better test coverage

---

### Rule 2: Use TestContainers for Real Databases

**Priority**: Medium

**Description**: Use TestContainers for integration tests that need real database behavior.

**Correct**:

```csharp
// Install: Testcontainers.MsSql

public class DatabaseTestFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container;

    public DatabaseTestFixture()
    {
        _container = new MsSqlBuilder()
            .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
            .WithPassword("YourStrong@Passw0rd")
            .Build();
    }

    public string ConnectionString => _container.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}

public class ProductsIntegrationTests : IClassFixture<DatabaseTestFixture>
{
    private readonly DatabaseTestFixture _fixture;

    public ProductsIntegrationTests(DatabaseTestFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task CreateProduct_PersistsToDatabase()
    {
        // Arrange
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(_fixture.ConnectionString)
            .Options;

        await using var context = new AppDbContext(options);
        await context.Database.EnsureCreatedAsync();

        // Act
        var product = new Product { Name = "Test", Price = 10.00m };
        context.Products.Add(product);
        await context.SaveChangesAsync();

        // Assert
        var saved = await context.Products.FindAsync(product.Id);
        Assert.NotNull(saved);
        Assert.Equal("Test", saved.Name);
    }
}
```

**Why**:
- Tests against real database
- Catches SQL-specific issues
- More realistic tests
- Better confidence

---

### Rule 3: Test Authentication and Authorization

**Priority**: High

**Description**: Test authenticated endpoints with proper test authentication.

**Correct**:

```csharp
// Custom authentication for tests
public class TestAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public TestAuthHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, "1"),
            new Claim(ClaimTypes.Name, "TestUser"),
            new Claim(ClaimTypes.Role, "Admin")
        };

        var identity = new ClaimsIdentity(claims, "Test");
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, "Test");

        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}

// Configure test authentication
public class WebApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            services.AddAuthentication("Test")
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", options => { });
        });
    }
}

// Test authenticated endpoint
[Fact]
public async Task GetOrders_RequiresAuthentication()
{
    // Act - without auth
    var response = await _client.GetAsync("/api/orders");

    // Assert
    Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
}

[Fact]
public async Task GetOrders_WithAuth_ReturnsOk()
{
    // Arrange
    _client.DefaultRequestHeaders.Authorization = 
        new AuthenticationHeaderValue("Test");

    // Act
    var response = await _client.GetAsync("/api/orders");

    // Assert
    response.EnsureSuccessStatusCode();
}
```

**Why**:
- Tests security requirements
- Validates authorization policies
- Ensures proper authentication flow
- Critical for secure APIs

---

## Integration Example

Complete integration test setup:

```csharp
// WebApiFactory.cs
public class WebApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Replace database
            var descriptor = services.SingleOrDefault(
                d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            services.Remove(descriptor);

            services.AddDbContext<AppDbContext>(options =>
                options.UseInMemoryDatabase("TestDb"));

            // Test authentication
            services.AddAuthentication("Test")
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { });
        });
    }
}

// Integration test
public class ProductsControllerIntegrationTests : IClassFixture<WebApiFactory>
{
    private readonly HttpClient _client;

    public ProductsControllerIntegrationTests(WebApiFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetProducts_ReturnsOk()
    {
        var response = await _client.GetAsync("/api/products");
        response.EnsureSuccessStatusCode();
    }
}
```

## Checklist

- [ ] WebApplicationFactory configured
- [ ] Test database isolated
- [ ] Authentication tested
- [ ] Authorization tested
- [ ] Full request/response cycle tested
- [ ] TestContainers for real database (if needed)
- [ ] Tests are independent

## References

- [Integration Tests](https://docs.microsoft.com/aspnet/core/test/integration-tests)
- [WebApplicationFactory](https://docs.microsoft.com/aspnet/core/test/integration-tests)

## Changelog

### v1.0.0
- Initial release
- 3 core rules for integration testing
