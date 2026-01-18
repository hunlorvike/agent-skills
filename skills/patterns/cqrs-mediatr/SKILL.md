---
name: cqrs-mediatr
description: Best practices for implementing CQRS (Command Query Responsibility Segregation) pattern with MediatR in ASP.NET Core including command/query handlers, validation pipelines, and event publishing.
version: 1.0.0
priority: medium
categories:
  - patterns
  - cqrs
  - architecture
use_when:
  - "When implementing CQRS pattern"
  - "When using MediatR library"
  - "When separating read/write models"
  - "When building complex business logic"
  - "When implementing command/query handlers"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "MediatR"
related_skills:
  - repository-unitofwork
  - dependency-injection-patterns
  - error-handling-patterns
---

# CQRS & MediatR Best Practices

## Overview

This skill covers implementing CQRS (Command Query Responsibility Segregation) pattern with MediatR in ASP.NET Core. CQRS separates read and write operations, improving scalability and maintainability. This skill addresses:

- CQRS implementation
- MediatR patterns
- Command/Query handlers
- Validation pipelines
- Event publishing
- Request/Response patterns

## Rules

### Rule 1: Separate Commands and Queries

**Priority**: High

**Description**: Clearly separate commands (write operations) from queries (read operations).

**Incorrect**:

```csharp
// Mixed command and query
public class OrderService
{
    public async Task<Order> GetOrderAndUpdateStatusAsync(int id, OrderStatus status)
    {
        var order = await _repository.GetByIdAsync(id); // Query
        order.Status = status; // Command
        await _repository.UpdateAsync(order); // Command
        return order; // Query result
    }
}
```

**Correct**:

```csharp
// Command - changes state
public record CreateOrderCommand : IRequest<OrderDto>
{
    public int CustomerId { get; init; }
    public List<OrderItemRequest> Items { get; init; } = new();
}

public record UpdateOrderStatusCommand : IRequest
{
    public int OrderId { get; init; }
    public OrderStatus Status { get; init; }
}

// Query - reads data
public record GetOrderQuery : IRequest<OrderDto?>
{
    public int OrderId { get; init; }
}

public record GetOrdersQuery : IRequest<List<OrderDto>>
{
    public int? CustomerId { get; init; }
    public OrderStatus? Status { get; init; }
}

// Command handler
public class CreateOrderCommandHandler : IRequestHandler<CreateOrderCommand, OrderDto>
{
    private readonly IOrderRepository _repository;
    private readonly IUnitOfWork _unitOfWork;

    public async Task<OrderDto> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        var order = new Order
        {
            CustomerId = request.CustomerId,
            Items = request.Items.Select(i => new OrderItem
            {
                ProductId = i.ProductId,
                Quantity = i.Quantity
            }).ToList()
        };

        _repository.Add(order);
        await _unitOfWork.SaveChangesAsync(ct);

        return _mapper.Map<OrderDto>(order);
    }
}

// Query handler
public class GetOrderQueryHandler : IRequestHandler<GetOrderQuery, OrderDto?>
{
    private readonly IOrderRepository _repository;

    public async Task<OrderDto?> Handle(GetOrderQuery request, CancellationToken ct)
    {
        var order = await _repository.GetByIdAsync(request.OrderId, ct);
        return order == null ? null : _mapper.Map<OrderDto>(order);
    }
}
```

**Why**:
- Clear separation of concerns
- Different optimization strategies
- Better scalability
- Easier to maintain
- CQRS principle

---

### Rule 2: Use MediatR for Request/Response

**Priority**: High

**Description**: Use MediatR to decouple controllers from business logic.

**Incorrect**:

```csharp
// Controller directly calls service
[ApiController]
public class OrdersController : ControllerBase
{
    private readonly IOrderService _orderService;

    public OrdersController(IOrderService orderService)
    {
        _orderService = orderService;
    }

    [HttpPost]
    public async Task<ActionResult<OrderDto>> CreateOrder(CreateOrderRequest request)
    {
        var order = await _orderService.CreateAsync(request); // Tight coupling
        return Ok(order);
    }
}
```

**Correct**:

```csharp
// Register MediatR
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(Program).Assembly));

// Controller uses MediatR
[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    private readonly IMediator _mediator;

    public OrdersController(IMediator mediator)
    {
        _mediator = mediator;
    }

    [HttpPost]
    [ProducesResponseType(typeof(OrderDto), StatusCodes.Status201Created)]
    public async Task<ActionResult<OrderDto>> CreateOrder(
        [FromBody] CreateOrderRequest request,
        CancellationToken ct)
    {
        var command = new CreateOrderCommand
        {
            CustomerId = request.CustomerId,
            Items = request.Items
        };

        var order = await _mediator.Send(command, ct);
        return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<OrderDto>> GetOrder(int id, CancellationToken ct)
    {
        var query = new GetOrderQuery { OrderId = id };
        var order = await _mediator.Send(query, ct);
        
        if (order == null)
            return NotFound();
        
        return Ok(order);
    }
}
```

**Why**:
- Decouples controllers from business logic
- Single responsibility
- Easier testing
- Better organization
- MediatR pattern

---

### Rule 3: Implement Validation Pipeline

**Priority**: High

**Description**: Use MediatR pipeline behaviors for validation.

**Incorrect**:

```csharp
// Validation in handler
public class CreateOrderCommandHandler : IRequestHandler<CreateOrderCommand, OrderDto>
{
    public async Task<OrderDto> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        // Validation mixed with business logic
        if (request.Items.Count == 0)
            throw new ValidationException("Items required");
        
        if (request.CustomerId <= 0)
            throw new ValidationException("Invalid customer ID");
        
        // Business logic
        var order = new Order { /* ... */ };
        return order;
    }
}
```

**Correct**:

```csharp
// Validation behavior
public class ValidationBehavior<TRequest, TResponse> : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationBehavior(IEnumerable<IValidator<TRequest>> validators)
    {
        _validators = validators;
    }

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (_validators.Any())
        {
            var context = new ValidationContext<TRequest>(request);
            var validationResults = await Task.WhenAll(
                _validators.Select(v => v.ValidateAsync(context, ct)));
            
            var failures = validationResults
                .SelectMany(r => r.Errors)
                .Where(f => f != null)
                .ToList();

            if (failures.Any())
            {
                throw new ValidationException(failures);
            }
        }

        return await next();
    }
}

// Register validation behavior
builder.Services.AddScoped(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));

// Validator
public class CreateOrderCommandValidator : AbstractValidator<CreateOrderCommand>
{
    public CreateOrderCommandValidator()
    {
        RuleFor(x => x.CustomerId)
            .GreaterThan(0)
            .WithMessage("Customer ID is required");

        RuleFor(x => x.Items)
            .NotEmpty()
            .WithMessage("At least one item is required");

        RuleForEach(x => x.Items)
            .SetValidator(new OrderItemRequestValidator());
    }
}

// Register validators
builder.Services.AddScoped<IValidator<CreateOrderCommand>, CreateOrderCommandValidator>();

// Handler is clean
public class CreateOrderCommandHandler : IRequestHandler<CreateOrderCommand, OrderDto>
{
    public async Task<OrderDto> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        // Validation already done by pipeline
        var order = new Order { /* ... */ };
        return order;
    }
}
```

**Why**:
- Separation of concerns
- Reusable validation
- Consistent validation
- Clean handlers
- Better organization

---

### Rule 4: Publish Domain Events

**Priority**: Medium

**Description**: Use MediatR to publish domain events after state changes.

**Incorrect**:

```csharp
// Events not published
public class CreateOrderCommandHandler : IRequestHandler<CreateOrderCommand, OrderDto>
{
    public async Task<OrderDto> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        var order = new Order { /* ... */ };
        await _repository.AddAsync(order);
        await _unitOfWork.SaveChangesAsync(ct);
        
        // Event not published - other services don't know
        return _mapper.Map<OrderDto>(order);
    }
}
```

**Correct**:

```csharp
// Domain event
public record OrderCreatedEvent : INotification
{
    public int OrderId { get; init; }
    public int CustomerId { get; init; }
    public decimal TotalAmount { get; init; }
    public DateTime CreatedAt { get; init; }
}

// Command handler publishes event
public class CreateOrderCommandHandler : IRequestHandler<CreateOrderCommand, OrderDto>
{
    private readonly IMediator _mediator;

    public async Task<OrderDto> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        var order = new Order { /* ... */ };
        await _repository.AddAsync(order);
        await _unitOfWork.SaveChangesAsync(ct);

        // Publish domain event
        await _mediator.Publish(new OrderCreatedEvent
        {
            OrderId = order.Id,
            CustomerId = order.CustomerId,
            TotalAmount = order.TotalAmount,
            CreatedAt = DateTime.UtcNow
        }, ct);

        return _mapper.Map<OrderDto>(order);
    }
}

// Event handler
public class OrderCreatedEventHandler : INotificationHandler<OrderCreatedEvent>
{
    private readonly IEmailService _emailService;
    private readonly ILogger<OrderCreatedEventHandler> _logger;

    public async Task Handle(OrderCreatedEvent notification, CancellationToken ct)
    {
        _logger.LogInformation("Order {OrderId} created, sending confirmation email", notification.OrderId);
        await _emailService.SendOrderConfirmationAsync(notification.OrderId, ct);
    }
}

// Multiple handlers for same event
public class OrderCreatedInventoryHandler : INotificationHandler<OrderCreatedEvent>
{
    public async Task Handle(OrderCreatedEvent notification, CancellationToken ct)
    {
        await _inventoryService.ReserveItemsAsync(notification.OrderId, ct);
    }
}
```

**Why**:
- Decouples event producers from consumers
- Multiple handlers per event
- Better domain modeling
- Event-driven architecture
- Scalable design

---

### Rule 5: Use Separate Read/Write Models

**Priority**: Medium

**Description**: Use different models for read and write operations when beneficial.

**Incorrect**:

```csharp
// Same model for read and write
public class Order
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public OrderStatus Status { get; set; }
    public ICollection<OrderItem> Items { get; set; } = new List<OrderItem>();
    // Used for both read and write
}

// Query returns full entity
public class GetOrderQueryHandler : IRequestHandler<GetOrderQuery, Order>
{
    public async Task<Order> Handle(GetOrderQuery request, CancellationToken ct)
    {
        return await _repository.GetByIdAsync(request.OrderId, ct);
    }
}
```

**Correct**:

```csharp
// Write model (domain entity)
public class Order
{
    public int Id { get; private set; }
    public int CustomerId { get; private set; }
    public OrderStatus Status { get; private set; }
    private readonly List<OrderItem> _items = new();
    public IReadOnlyCollection<OrderItem> Items => _items.AsReadOnly();

    public void AddItem(OrderItem item)
    {
        _items.Add(item);
    }

    public void ChangeStatus(OrderStatus newStatus)
    {
        Status = newStatus;
    }
}

// Read model (DTO)
public record OrderDto
{
    public int Id { get; init; }
    public int CustomerId { get; init; }
    public string CustomerName { get; init; } = string.Empty;
    public OrderStatus Status { get; init; }
    public decimal TotalAmount { get; init; }
    public List<OrderItemDto> Items { get; init; } = new();
}

// Query handler uses read model
public class GetOrderQueryHandler : IRequestHandler<GetOrderQuery, OrderDto?>
{
    private readonly IOrderReadRepository _readRepository;

    public async Task<OrderDto?> Handle(GetOrderQuery request, CancellationToken ct)
    {
        return await _readRepository.GetOrderDtoAsync(request.OrderId, ct);
    }
}

// Separate read repository (optimized for reads)
public interface IOrderReadRepository
{
    Task<OrderDto?> GetOrderDtoAsync(int id, CancellationToken ct = default);
    Task<List<OrderDto>> GetOrdersAsync(GetOrdersQuery query, CancellationToken ct = default);
}

// Write repository (for commands)
public interface IOrderWriteRepository
{
    Task<Order> GetByIdAsync(int id, CancellationToken ct = default);
    Task AddAsync(Order order, CancellationToken ct = default);
    Task UpdateAsync(Order order, CancellationToken ct = default);
}
```

**Why**:
- Optimized read models
- Different scaling strategies
- Better performance
- Clear separation
- CQRS benefit

---

## Integration Example

Complete CQRS/MediatR setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// MediatR
builder.Services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssembly(typeof(Program).Assembly);
});

// Validation pipeline
builder.Services.AddScoped(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));

// FluentValidation
builder.Services.AddValidatorsFromAssembly(typeof(Program).Assembly);

// Repositories
builder.Services.AddScoped<IOrderWriteRepository, OrderWriteRepository>();
builder.Services.AddScoped<IOrderReadRepository, OrderReadRepository>();

var app = builder.Build();
app.MapControllers();
app.Run();
```

## Checklist

- [ ] Commands and queries separated
- [ ] MediatR configured
- [ ] Validation pipeline implemented
- [ ] Domain events published
- [ ] Separate read/write models (if beneficial)
- [ ] Handlers are testable
- [ ] Error handling in handlers

## References

- [MediatR Documentation](https://github.com/jbogard/MediatR)
- [CQRS Pattern](https://docs.microsoft.com/azure/architecture/patterns/cqrs)
- [FluentValidation](https://docs.fluentvalidation.net/)

## Changelog

### v1.0.0
- Initial release
- 5 core rules for CQRS & MediatR
