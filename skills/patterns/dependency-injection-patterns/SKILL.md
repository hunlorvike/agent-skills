---
name: dependency-injection-patterns
description: Best practices for dependency injection in ASP.NET Core including service lifetimes, factory patterns, Options pattern, and avoiding anti-patterns like service locator.
version: 1.0.0
priority: medium
categories:
  - patterns
  - dependency-injection
use_when:
  - "When designing service registration"
  - "When resolving dependencies"
  - "When implementing factory patterns"
  - "When configuring service lifetimes"
  - "When using Options pattern"
prerequisites:
  - "ASP.NET Core 8.0+"
related_skills:
  - background-jobs-tasks
  - configuration-management
  - repository-unitofwork
---

# Dependency Injection Patterns Best Practices

## Overview

This skill covers advanced dependency injection patterns in ASP.NET Core. Proper DI usage is fundamental to building maintainable, testable applications. This skill addresses:

- Service lifetimes (Singleton, Scoped, Transient)
- Factory patterns
- Options pattern
- Named services
- Service locator anti-pattern
- Dependency resolution

## Rules

### Rule 1: Understand Service Lifetimes

**Priority**: Critical

**Description**: Use the correct service lifetime based on usage patterns and dependencies.

**Incorrect**:

```csharp
// Wrong lifetime - DbContext as Singleton
builder.Services.AddSingleton<AppDbContext>(provider =>
{
    var options = provider.GetRequiredService<DbContextOptions<AppDbContext>>();
    return new AppDbContext(options); // DbContext is not thread-safe!
});

// Scoped service in Singleton
builder.Services.AddSingleton<IOrderService, OrderService>(); // OrderService uses DbContext (scoped)

// Transient for expensive operations
builder.Services.AddTransient<IReportGenerator, ReportGenerator>(); // Creates new instance every time - expensive
```

**Correct**:

```csharp
// DbContext should be Scoped
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString)); // Default is Scoped

// Services that use DbContext should be Scoped
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<IOrderService, OrderService>();

// Stateless services can be Singleton
builder.Services.AddSingleton<ICacheService, CacheService>();
builder.Services.AddSingleton<IMapper, Mapper>(); // AutoMapper

// Expensive to create - use Singleton
builder.Services.AddSingleton<IReportGenerator, ReportGenerator>();

// Lightweight, stateless - can be Transient
builder.Services.AddTransient<IValidator<CreateOrderRequest>, CreateOrderRequestValidator>();

// Lifetime guidelines:
// - Singleton: Stateless, thread-safe, expensive to create
// - Scoped: Per-request, uses scoped dependencies (DbContext)
// - Transient: Lightweight, new instance every time
```

**Why**:
- Wrong lifetime causes bugs (DbContext in Singleton = thread safety issues)
- Memory leaks (Singleton holding scoped dependencies)
- Performance issues (Transient for expensive objects)
- Essential for proper resource management

---

### Rule 2: Use Factory Pattern for Complex Creation

**Priority**: High

**Description**: Use factory pattern when service creation requires complex logic or conditional logic.

**Incorrect**:

```csharp
// Complex creation logic in registration
builder.Services.AddScoped<IEmailService>(provider =>
{
    var config = provider.GetRequiredService<IConfiguration>();
    var env = provider.GetRequiredService<IHostEnvironment>();
    var logger = provider.GetRequiredService<ILogger<EmailService>>();
    
    if (env.IsDevelopment())
    {
        return new ConsoleEmailService(logger);
    }
    else if (config["Email:Provider"] == "SendGrid")
    {
        var apiKey = config["Email:SendGrid:ApiKey"];
        return new SendGridEmailService(apiKey, logger);
    }
    else
    {
        var smtpHost = config["Email:Smtp:Host"];
        var smtpPort = config.GetValue<int>("Email:Smtp:Port");
        return new SmtpEmailService(smtpHost, smtpPort, logger);
    }
    // Complex logic in registration - hard to test
});
```

**Correct**:

```csharp
// Factory interface
public interface IEmailServiceFactory
{
    IEmailService Create();
}

// Factory implementation
public class EmailServiceFactory : IEmailServiceFactory
{
    private readonly IServiceProvider _serviceProvider;
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;

    public EmailServiceFactory(
        IServiceProvider serviceProvider,
        IConfiguration configuration,
        IHostEnvironment environment)
    {
        _serviceProvider = serviceProvider;
        _configuration = configuration;
        _environment = environment;
    }

    public IEmailService Create()
    {
        var logger = _serviceProvider.GetRequiredService<ILogger<EmailService>>();
        
        if (_environment.IsDevelopment())
        {
            return new ConsoleEmailService(logger);
        }

        var provider = _configuration["Email:Provider"];
        return provider switch
        {
            "SendGrid" => new SendGridEmailService(
                _configuration["Email:SendGrid:ApiKey"]!,
                logger),
            "Smtp" => new SmtpEmailService(
                _configuration["Email:Smtp:Host"]!,
                _configuration.GetValue<int>("Email:Smtp:Port"),
                logger),
            _ => throw new InvalidOperationException($"Unknown email provider: {provider}")
        };
    }
}

// Register factory
builder.Services.AddSingleton<IEmailServiceFactory, EmailServiceFactory>();

// Or use Func factory
builder.Services.AddScoped<IEmailService>(provider =>
{
    var factory = provider.GetRequiredService<IEmailServiceFactory>();
    return factory.Create();
});

// Or use typed factory
public interface ITypedFactory<T>
{
    T Create();
}

// Usage
public class OrderService
{
    private readonly IEmailServiceFactory _emailFactory;

    public OrderService(IEmailServiceFactory emailFactory)
    {
        _emailFactory = emailFactory;
    }

    public async Task ProcessOrderAsync(int orderId)
    {
        var emailService = _emailFactory.Create(); // Create when needed
        await emailService.SendConfirmationAsync(orderId);
    }
}
```

**Why**:
- Separates creation logic
- Testable factory
- Flexible service creation
- Better organization
- Supports conditional logic

---

### Rule 3: Use Options Pattern for Configuration

**Priority**: High

**Description**: Use Options pattern instead of directly accessing IConfiguration.

**Incorrect**:

```csharp
// Direct IConfiguration access - not type-safe
public class EmailService
{
    private readonly IConfiguration _configuration;

    public EmailService(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public async Task SendAsync(string to, string subject, string body)
    {
        var smtpHost = _configuration["Email:Smtp:Host"]; // Magic strings
        var smtpPort = _configuration.GetValue<int>("Email:Smtp:Port");
        var from = _configuration["Email:From"];
        // No validation, no IntelliSense
    }
}
```

**Correct**:

```csharp
// Options class
public class EmailOptions
{
    public const string SectionName = "Email";

    public string Provider { get; set; } = string.Empty;
    public string From { get; set; } = string.Empty;
    public SmtpOptions Smtp { get; set; } = new();
    public SendGridOptions SendGrid { get; set; } = new();
}

public class SmtpOptions
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; } = 587;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

// Register options
builder.Services.Configure<EmailOptions>(
    builder.Configuration.GetSection(EmailOptions.SectionName));

// Validate options
builder.Services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection(EmailOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart(); // Fail fast if invalid

// Or use FluentValidation
builder.Services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection(EmailOptions.SectionName))
    .Validate<EmailOptions>(options =>
    {
        if (string.IsNullOrEmpty(options.From))
            return false;
        return options.Provider switch
        {
            "Smtp" => !string.IsNullOrEmpty(options.Smtp.Host),
            "SendGrid" => !string.IsNullOrEmpty(options.SendGrid.ApiKey),
            _ => false
        };
    }, "Email configuration is invalid")
    .ValidateOnStart();

// Use in service
public class EmailService
{
    private readonly EmailOptions _options;
    private readonly ILogger<EmailService> _logger;

    public EmailService(
        IOptions<EmailOptions> options,
        ILogger<EmailService> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    public async Task SendAsync(string to, string subject, string body)
    {
        // Type-safe access
        _logger.LogInformation("Sending email via {Provider} from {From}", 
            _options.Provider, _options.From);
        
        // Use _options.Smtp.Host, etc.
    }
}

// IOptionsSnapshot for reloadable options
public class EmailService
{
    private readonly IOptionsSnapshot<EmailOptions> _options;

    public EmailService(IOptionsSnapshot<EmailOptions> options)
    {
        _options = options; // Can reload on change
    }

    public void UseOptions()
    {
        var currentOptions = _options.Value; // Gets latest value
    }
}
```

**Why**:
- Type-safe configuration
- IntelliSense support
- Configuration validation
- Reloadable options
- Better organization

---

### Rule 4: Avoid Service Locator Anti-Pattern

**Priority**: Critical

**Description**: Never use service locator pattern. Inject dependencies explicitly.

**Incorrect**:

```csharp
// Service locator anti-pattern
public class OrderService
{
    private readonly IServiceProvider _serviceProvider;

    public OrderService(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }

    public async Task ProcessOrderAsync(int id)
    {
        // Resolving dependencies at runtime - hides dependencies
        var emailService = _serviceProvider.GetRequiredService<IEmailService>();
        var logger = _serviceProvider.GetRequiredService<ILogger<OrderService>>();
        var repository = _serviceProvider.GetRequiredService<IOrderRepository>();
        // Dependencies are not clear from constructor
    }
}

// Static service locator - worst practice
public class OrderService
{
    public async Task ProcessOrderAsync(int id)
    {
        var emailService = ServiceLocator.GetService<IEmailService>(); // Hidden dependency
    }
}
```

**Correct**:

```csharp
// Explicit dependency injection
public class OrderService
{
    private readonly IOrderRepository _repository;
    private readonly IEmailService _emailService;
    private readonly ILogger<OrderService> _logger;

    public OrderService(
        IOrderRepository repository,
        IEmailService emailService,
        ILogger<OrderService> logger)
    {
        _repository = repository;
        _emailService = emailService;
        _logger = logger;
        // All dependencies clear from constructor
    }

    public async Task ProcessOrderAsync(int id)
    {
        var order = await _repository.GetByIdAsync(id);
        await _emailService.SendConfirmationAsync(order.Id);
        _logger.LogInformation("Order {OrderId} processed", id);
    }
}

// Only use IServiceProvider for factory pattern
public class OrderServiceFactory
{
    private readonly IServiceProvider _serviceProvider;

    public OrderServiceFactory(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }

    public IOrderService Create(string orderType)
    {
        // Factory pattern - acceptable use of service provider
        return orderType switch
        {
            "standard" => _serviceProvider.GetRequiredService<StandardOrderService>(),
            "premium" => _serviceProvider.GetRequiredService<PremiumOrderService>(),
            _ => throw new ArgumentException($"Unknown order type: {orderType}")
        };
    }
}
```

**Why**:
- Dependencies are explicit
- Easier to test
- Better code clarity
- Prevents hidden dependencies
- Industry best practice

---

### Rule 5: Register Services by Interface

**Priority**: High

**Description**: Always register services by their interface, not concrete type.

**Incorrect**:

```csharp
// Registering concrete types
builder.Services.AddScoped<OrderService>(); // Can't mock in tests
builder.Services.AddScoped<ProductService>();

// Using concrete types in controllers
public class OrdersController : ControllerBase
{
    private readonly OrderService _orderService; // Tight coupling

    public OrdersController(OrderService orderService)
    {
        _orderService = orderService;
    }
}
```

**Correct**:

```csharp
// Register by interface
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IProductService, ProductService>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();

// Use interfaces in controllers
public class OrdersController : ControllerBase
{
    private readonly IOrderService _orderService; // Loose coupling

    public OrdersController(IOrderService orderService)
    {
        _orderService = orderService;
    }
}

// Multiple implementations
public interface IEmailService { }
public class SmtpEmailService : IEmailService { }
public class SendGridEmailService : IEmailService { }

// Register multiple, resolve by name or factory
builder.Services.AddScoped<IEmailService, SmtpEmailService>();
// Or use factory to choose implementation
```

**Why**:
- Enables mocking in tests
- Loose coupling
- Easy to swap implementations
- Better design
- Dependency inversion principle

---

### Rule 6: Handle Scoped Services in Background Jobs

**Priority**: High

**Description**: Create scopes when using scoped services in singleton services or background jobs.

**Incorrect**:

```csharp
// Scoped service in singleton - won't work
builder.Services.AddSingleton<OrderProcessingService>();
builder.Services.AddScoped<IOrderRepository, OrderRepository>();

public class OrderProcessingService : BackgroundService
{
    private readonly IOrderRepository _repository; // Error: scoped in singleton

    public OrderProcessingService(IOrderRepository repository)
    {
        _repository = repository;
    }
}
```

**Correct**:

```csharp
// Create scope for scoped services
public class OrderProcessingService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;

    public OrderProcessingService(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            using var scope = _serviceProvider.CreateScope();
            var repository = scope.ServiceProvider.GetRequiredService<IOrderRepository>();
            var emailService = scope.ServiceProvider.GetRequiredService<IEmailService>();
            
            // Use scoped services
            var orders = await repository.GetPendingOrdersAsync(stoppingToken);
            foreach (var order in orders)
            {
                await emailService.SendConfirmationAsync(order.Id, stoppingToken);
            }
            
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }
}
```

**Why**:
- Proper service lifetime management
- Prevents memory leaks
- Correct DI usage
- Essential for EF Core
- Best practice

---

### Rule 7: Use Named Services When Needed

**Priority**: Medium

**Description**: Use named services or keyed services for multiple implementations of the same interface.

**Incorrect**:

```csharp
// Registering multiple implementations - last one wins
builder.Services.AddScoped<IEmailService, SmtpEmailService>();
builder.Services.AddScoped<IEmailService, SendGridEmailService>(); // This replaces the first

// Resolving gets last registered
var emailService = serviceProvider.GetRequiredService<IEmailService>(); // Always SendGridEmailService
```

**Correct**:

```csharp
// Using keyed services (.NET 8+)
builder.Services.AddKeyedScoped<IEmailService, SmtpEmailService>("smtp");
builder.Services.AddKeyedScoped<IEmailService, SendGridEmailService>("sendgrid");

// Resolve by key
public class OrderService
{
    private readonly IEmailService _emailService;

    public OrderService([FromKeyedServices("smtp")] IEmailService emailService)
    {
        _emailService = emailService;
    }
}

// Or resolve dynamically
public class EmailServiceFactory
{
    private readonly IServiceProvider _serviceProvider;

    public IEmailService GetEmailService(string provider)
    {
        return provider switch
        {
            "smtp" => _serviceProvider.GetRequiredKeyedService<IEmailService>("smtp"),
            "sendgrid" => _serviceProvider.GetRequiredKeyedService<IEmailService>("sendgrid"),
            _ => throw new ArgumentException($"Unknown provider: {provider}")
        };
    }
}

// Or use separate interfaces
public interface ISmtpEmailService : IEmailService { }
public interface ISendGridEmailService : IEmailService { }

builder.Services.AddScoped<ISmtpEmailService, SmtpEmailService>();
builder.Services.AddScoped<ISendGridEmailService, SendGridEmailService>();
```

**Why**:
- Multiple implementations support
- Clear service selection
- Type-safe resolution
- Better organization
- Flexible design

---

## Integration Example

Complete DI setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// DbContext (Scoped)
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));

// Repositories (Scoped)
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<IProductRepository, ProductRepository>();

// Services (Scoped)
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IProductService, ProductService>();

// Stateless services (Singleton)
builder.Services.AddSingleton<ICacheService, CacheService>();
builder.Services.AddSingleton<IEmailServiceFactory, EmailServiceFactory>();

// Options
builder.Services.Configure<EmailOptions>(
    builder.Configuration.GetSection(EmailOptions.SectionName));

// Validators (Transient)
builder.Services.AddTransient<IValidator<CreateOrderRequest>, CreateOrderRequestValidator>();

var app = builder.Build();
app.Run();
```

## Checklist

- [ ] Correct service lifetimes used
- [ ] Factory pattern for complex creation
- [ ] Options pattern for configuration
- [ ] No service locator anti-pattern
- [ ] Services registered by interface
- [ ] Scoped services handled correctly in background jobs
- [ ] Named/keyed services when needed
- [ ] Dependencies are explicit

## References

- [Dependency Injection](https://docs.microsoft.com/aspnet/core/fundamentals/dependency-injection)
- [Service Lifetimes](https://docs.microsoft.com/aspnet/core/fundamentals/dependency-injection#service-lifetimes)
- [Options Pattern](https://docs.microsoft.com/aspnet/core/fundamentals/configuration/options)

## Changelog

### v1.0.0
- Initial release
- 7 core rules for dependency injection
