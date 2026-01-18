---
name: message-queues-event-driven
description: Best practices for implementing message queues and event-driven architecture in ASP.NET Core using RabbitMQ, Azure Service Bus, MassTransit, and event publishing patterns.
version: 1.0.0
priority: medium
categories:
  - messaging
  - event-driven
  - patterns
use_when:
  - "When implementing message queues"
  - "When building event-driven architecture"
  - "When decoupling services"
  - "When implementing pub/sub patterns"
  - "When processing asynchronous work"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "MassTransit or Azure.Messaging.ServiceBus"
related_skills:
  - background-jobs-tasks
  - error-handling-patterns
  - structured-logging
---

# Message Queues & Event-Driven Architecture

## Overview

This skill covers implementing message queues and event-driven architecture in ASP.NET Core. Message queues enable asynchronous communication, service decoupling, and reliable message processing. This skill addresses:

- Message queue patterns
- Event-driven architecture
- Message serialization
- Dead letter queues
- Idempotency
- Message ordering

## Rules

### Rule 1: Use MassTransit for Message Queues

**Priority**: High

**Description**: Use MassTransit as abstraction layer over message brokers for better portability and features.

**Incorrect**:

```csharp
// Direct RabbitMQ usage - vendor lock-in
using RabbitMQ.Client;

public class OrderService
{
    private readonly IConnection _connection;
    private readonly IModel _channel;

    public OrderService()
    {
        var factory = new ConnectionFactory { HostName = "localhost" };
        _connection = factory.CreateConnection();
        _channel = _connection.CreateModel();
        // Low-level API, error-prone
    }

    public void PublishOrderCreated(int orderId)
    {
        _channel.BasicPublish(
            exchange: "orders",
            routingKey: "order.created",
            body: Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { OrderId = orderId })));
        // No retry, no error handling, no idempotency
    }
}
```

**Correct**:

```csharp
// MassTransit configuration
builder.Services.AddMassTransit(x =>
{
    x.UsingRabbitMq((context, cfg) =>
    {
        cfg.Host("localhost", "/", h =>
        {
            h.Username("guest");
            h.Password("guest");
        });

        cfg.ConfigureEndpoints(context);
    });

    // Or Azure Service Bus
    // x.UsingAzureServiceBus((context, cfg) =>
    // {
    //     cfg.Host(builder.Configuration.GetConnectionString("ServiceBus"));
    //     cfg.ConfigureEndpoints(context);
    // });
});

// Message contract
public record OrderCreatedEvent
{
    public int OrderId { get; init; }
    public int CustomerId { get; init; }
    public decimal TotalAmount { get; init; }
    public DateTime CreatedAt { get; init; }
}

// Publisher
public class OrderService
{
    private readonly IPublishEndpoint _publishEndpoint;
    private readonly ILogger<OrderService> _logger;

    public OrderService(
        IPublishEndpoint publishEndpoint,
        ILogger<OrderService> logger)
    {
        _publishEndpoint = publishEndpoint;
        _logger = logger;
    }

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        var order = await _repository.CreateAsync(request);
        
        // Publish event
        await _publishEndpoint.Publish(new OrderCreatedEvent
        {
            OrderId = order.Id,
            CustomerId = order.CustomerId,
            TotalAmount = order.TotalAmount,
            CreatedAt = DateTime.UtcNow
        });

        _logger.LogInformation("Order {OrderId} created and event published", order.Id);
        return order;
    }
}

// Consumer
public class OrderCreatedConsumer : IConsumer<OrderCreatedEvent>
{
    private readonly IEmailService _emailService;
    private readonly ILogger<OrderCreatedConsumer> _logger;

    public OrderCreatedConsumer(
        IEmailService emailService,
        ILogger<OrderCreatedConsumer> logger)
    {
        _emailService = emailService;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        var message = context.Message;
        
        _logger.LogInformation(
            "Processing OrderCreated event for order {OrderId}",
            message.OrderId);

        await _emailService.SendOrderConfirmationAsync(message.OrderId);
        
        _logger.LogInformation("Order confirmation sent for order {OrderId}", message.OrderId);
    }
}

// Register consumer
builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<OrderCreatedConsumer>();
    x.AddConsumer<OrderCancelledConsumer>();
    
    x.UsingRabbitMq((context, cfg) =>
    {
        cfg.Host("localhost");
        cfg.ConfigureEndpoints(context);
    });
});
```

**Why**:
- Abstraction over message brokers
- Built-in retry and error handling
- Better features (sagas, routing, etc.)
- Easier testing
- Vendor portability

---

### Rule 2: Implement Idempotency

**Priority**: High

**Description**: Ensure message processing is idempotent to handle duplicate messages safely.

**Incorrect**:

```csharp
// Not idempotent - duplicate messages cause issues
public class OrderCreatedConsumer : IConsumer<OrderCreatedEvent>
{
    public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        var orderId = context.Message.OrderId;
        
        // If message is processed twice, email sent twice
        await _emailService.SendOrderConfirmationAsync(orderId);
        
        // If message is processed twice, inventory updated twice
        await _inventoryService.UpdateAsync(orderId);
    }
}
```

**Correct**:

```csharp
// Idempotent message processing
public class OrderCreatedConsumer : IConsumer<OrderCreatedEvent>
{
    private readonly IProcessedMessageRepository _processedMessages;
    private readonly IEmailService _emailService;

    public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        var messageId = context.MessageId.ToString();
        var orderId = context.Message.OrderId;

        // Check if already processed
        if (await _processedMessages.IsProcessedAsync(messageId))
        {
            _logger.LogWarning(
                "Message {MessageId} for order {OrderId} already processed, skipping",
                messageId,
                orderId);
            return; // Idempotent - safe to skip
        }

        try
        {
            // Process message
            await _emailService.SendOrderConfirmationAsync(orderId);
            await _inventoryService.UpdateAsync(orderId);

            // Mark as processed
            await _processedMessages.MarkAsProcessedAsync(messageId, orderId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process message {MessageId}", messageId);
            throw; // Will retry
        }
    }
}

// Or use message deduplication
public class OrderCreatedConsumer : IConsumer<OrderCreatedEvent>
{
    public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        var orderId = context.Message.OrderId;
        
        // Check if order already processed (using order state)
        var order = await _orderRepository.GetByIdAsync(orderId);
        if (order.ConfirmationEmailSent)
        {
            _logger.LogInformation(
                "Order {OrderId} already processed, skipping duplicate message",
                orderId);
            return; // Idempotent
        }

        await _emailService.SendOrderConfirmationAsync(orderId);
        order.ConfirmationEmailSent = true;
        await _orderRepository.UpdateAsync(order);
    }
}
```

**Why**:
- Handles duplicate messages safely
- Prevents duplicate processing
- Essential for reliability
- Better user experience
- Production requirement

---

### Rule 3: Handle Dead Letter Queues

**Priority**: High

**Description**: Configure dead letter queues for messages that fail repeatedly.

**Incorrect**:

```csharp
// No dead letter queue - failed messages lost
public class OrderCreatedConsumer : IConsumer<OrderCreatedEvent>
{
    public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        await _emailService.SendOrderConfirmationAsync(context.Message.OrderId);
        // If this fails repeatedly, message is lost
    }
}
```

**Correct**:

```csharp
// Configure retry and dead letter queue
builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<OrderCreatedConsumer>(cfg =>
    {
        cfg.UseMessageRetry(r => r
            .Interval(3, TimeSpan.FromSeconds(5))
            .Handle<TransientException>());
        
        cfg.UseInMemoryOutbox(); // Idempotency
    });

    x.UsingRabbitMq((context, cfg) =>
    {
        cfg.Host("localhost");

        // Configure dead letter exchange
        cfg.ReceiveEndpoint("order-created", e =>
        {
            e.ConfigureConsumer<OrderCreatedConsumer>(context);
            
            // Dead letter queue configuration
            e.BindDeadLetterQueue("order-created-dlq", "order-created-dlx");
            
            // Retry policy
            e.UseMessageRetry(r => r
                .Exponential(5, TimeSpan.FromSeconds(1), TimeSpan.FromMinutes(5))
                .Handle<TransientException>());
        });
    });
});

// Dead letter queue consumer
public class DeadLetterConsumer : IConsumer<OrderCreatedEvent>
{
    private readonly ILogger<DeadLetterConsumer> _logger;
    private readonly IAlertService _alertService;

    public async Task Consume(ConsumeContext<OrderCreatedEvent> context)
    {
        var message = context.Message;
        
        _logger.LogError(
            "Message for order {OrderId} moved to dead letter queue after retries exhausted",
            message.OrderId);

        // Alert operations team
        await _alertService.SendAlertAsync(
            $"Order {message.OrderId} processing failed after retries",
            AlertSeverity.High);

        // Store for manual review
        await _failedMessageRepository.StoreAsync(new FailedMessage
        {
            MessageId = context.MessageId.ToString(),
            OrderId = message.OrderId,
            FailedAt = DateTime.UtcNow,
            ErrorDetails = context.GetException()?.ToString()
        });
    }
}
```

**Why**:
- Prevents message loss
- Enables manual review
- Alerts on persistent failures
- Better observability
- Production reliability

---

### Rule 4: Use Event Sourcing When Appropriate

**Priority**: Medium

**Description**: Consider event sourcing for audit trails and event replay.

**Correct**:

```csharp
// Event store
public interface IEventStore
{
    Task AppendAsync(string streamId, IEnumerable<IDomainEvent> events);
    Task<IEnumerable<IDomainEvent>> GetEventsAsync(string streamId);
}

// Domain events
public interface IDomainEvent
{
    DateTime OccurredAt { get; }
}

public record OrderCreatedEvent : IDomainEvent
{
    public int OrderId { get; init; }
    public int CustomerId { get; init; }
    public DateTime OccurredAt { get; init; } = DateTime.UtcNow;
}

public record OrderStatusChangedEvent : IDomainEvent
{
    public int OrderId { get; init; }
    public OrderStatus OldStatus { get; init; }
    public OrderStatus NewStatus { get; init; }
    public DateTime OccurredAt { get; init; } = DateTime.UtcNow;
}

// Aggregate with event sourcing
public class Order
{
    private readonly List<IDomainEvent> _domainEvents = new();

    public int Id { get; private set; }
    public OrderStatus Status { get; private set; }

    public void ChangeStatus(OrderStatus newStatus)
    {
        var oldStatus = Status;
        Status = newStatus;
        
        _domainEvents.Add(new OrderStatusChangedEvent
        {
            OrderId = Id,
            OldStatus = oldStatus,
            NewStatus = newStatus
        });
    }

    public IEnumerable<IDomainEvent> GetUncommittedEvents() => _domainEvents;
    public void MarkEventsAsCommitted() => _domainEvents.Clear();
}

// Event handler
public class OrderEventHandler
{
    private readonly IEventStore _eventStore;
    private readonly IPublishEndpoint _publishEndpoint;

    public async Task HandleOrderCreatedAsync(OrderCreatedEvent @event)
    {
        // Store event
        await _eventStore.AppendAsync($"order-{@event.OrderId}", new[] { @event });
        
        // Publish to message queue
        await _publishEndpoint.Publish(@event);
    }
}
```

**Why**:
- Complete audit trail
- Event replay capability
- Time travel debugging
- Better domain modeling
- Advanced pattern

---

### Rule 5: Serialize Messages Properly

**Priority**: High

**Description**: Use proper serialization format for messages (JSON recommended).

**Incorrect**:

```csharp
// Binary serialization - not portable
public class OrderCreatedEvent
{
    // Binary serialization - tight coupling
}

// XML serialization - verbose
[XmlRoot("OrderCreated")]
public class OrderCreatedEvent
{
    // XML is verbose and harder to work with
}
```

**Correct**:

```csharp
// JSON serialization (recommended)
public record OrderCreatedEvent
{
    public int OrderId { get; init; }
    public int CustomerId { get; init; }
    public decimal TotalAmount { get; init; }
    public DateTime CreatedAt { get; init; }
    // JSON serialization is human-readable and portable
}

// Configure MassTransit serialization
builder.Services.AddMassTransit(x =>
{
    x.UsingRabbitMq((context, cfg) =>
    {
        cfg.Host("localhost");
        
        // Use JSON serializer (default)
        cfg.UseJsonSerializer();
        
        // Or configure custom serializer
        // cfg.UseNewtonsoftJsonSerializer();
    });
});

// Versioned messages for compatibility
public record OrderCreatedEventV1
{
    public int OrderId { get; init; }
    public int CustomerId { get; init; }
}

public record OrderCreatedEventV2
{
    public int OrderId { get; init; }
    public int CustomerId { get; init; }
    public string CustomerEmail { get; init; } = string.Empty; // New field
}
```

**Why**:
- Human-readable
- Portable across languages
- Easy debugging
- Versioning support
- Industry standard

---

## Integration Example

Complete message queue setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// MassTransit
builder.Services.AddMassTransit(x =>
{
    x.AddConsumer<OrderCreatedConsumer>();
    x.AddConsumer<OrderCancelledConsumer>();
    
    x.UsingRabbitMq((context, cfg) =>
    {
        cfg.Host(builder.Configuration["RabbitMQ:Host"], h =>
        {
            h.Username(builder.Configuration["RabbitMQ:Username"]);
            h.Password(builder.Configuration["RabbitMQ:Password"]);
        });

        cfg.ConfigureEndpoints(context);
    });
});

var app = builder.Build();
app.Run();
```

## Checklist

- [ ] MassTransit or message broker configured
- [ ] Message contracts defined
- [ ] Idempotency implemented
- [ ] Dead letter queues configured
- [ ] Retry policies configured
- [ ] Message serialization chosen (JSON)
- [ ] Event sourcing considered (if needed)
- [ ] Error handling in consumers

## References

- [MassTransit Documentation](https://masstransit.io/)
- [Azure Service Bus](https://docs.microsoft.com/azure/service-bus-messaging/)
- [RabbitMQ Best Practices](https://www.rabbitmq.com/best-practices.html)

## Changelog

### v1.0.0
- Initial release
- 5 core rules for message queues
