---
name: background-jobs-tasks
description: Best practices for implementing background jobs and scheduled tasks in ASP.NET Core using hosted services, Hangfire, Quartz.NET, and background processing patterns.
version: 1.0.0
priority: high
categories:
  - patterns
  - background-jobs
  - scheduling
use_when:
  - "When implementing background processing"
  - "When scheduling recurring tasks"
  - "When processing long-running operations"
  - "When offloading work from request pipeline"
  - "When implementing job queues"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Hangfire or Quartz.NET (optional)"
related_skills:
  - structured-logging
  - error-handling-patterns
  - caching-strategies
---

# Background Jobs & Tasks Best Practices

## Overview

This skill covers implementing background jobs and scheduled tasks in ASP.NET Core. Background processing is essential for offloading work from the request pipeline, scheduling recurring tasks, and handling long-running operations. This skill addresses:

- Hosted services pattern
- Hangfire configuration
- Quartz.NET scheduling
- Background job best practices
- Retry and error handling
- Job monitoring

## Rules

### Rule 1: Use Hosted Services for Simple Background Tasks

**Priority**: High

**Description**: Use IHostedService for simple, always-running background tasks.

**Incorrect**:

```csharp
// Background task in controller - blocks request
[HttpPost("orders/{id}/process")]
public async Task<IActionResult> ProcessOrder(int id)
{
    // Long-running operation blocks request
    await _emailService.SendConfirmationAsync(id);
    await _inventoryService.UpdateAsync(id);
    await _analyticsService.TrackAsync(id);
    return Ok();
}

// Using Task.Run - not recommended
[HttpPost("orders/{id}/process")]
public IActionResult ProcessOrder(int id)
{
    Task.Run(async () =>
    {
        await ProcessOrderAsync(id); // Fire and forget - no error handling
    });
    return Ok();
}
```

**Correct**:

```csharp
// Hosted service for background processing
public class OrderProcessingService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<OrderProcessingService> _logger;

    public OrderProcessingService(
        IServiceProvider serviceProvider,
        ILogger<OrderProcessingService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ProcessPendingOrdersAsync(stoppingToken);
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in order processing service");
                await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
            }
        }
    }

    private async Task ProcessPendingOrdersAsync(CancellationToken ct)
    {
        using var scope = _serviceProvider.CreateScope();
        var orderService = scope.ServiceProvider.GetRequiredService<IOrderService>();
        
        var pendingOrders = await orderService.GetPendingOrdersAsync(ct);
        
        foreach (var order in pendingOrders)
        {
            if (ct.IsCancellationRequested)
                break;

            try
            {
                await orderService.ProcessOrderAsync(order.Id, ct);
                _logger.LogInformation("Processed order {OrderId}", order.Id);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to process order {OrderId}", order.Id);
            }
        }
    }
}

// Register hosted service
builder.Services.AddHostedService<OrderProcessingService>();

// Or use IHostedService interface
public class CleanupService : IHostedService
{
    private Timer? _timer;

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _timer = new Timer(DoWork, null, TimeSpan.Zero, TimeSpan.FromHours(1));
        return Task.CompletedTask;
    }

    private void DoWork(object? state)
    {
        // Cleanup logic
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _timer?.Change(Timeout.Infinite, 0);
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        _timer?.Dispose();
    }
}
```

**Why**:
- Non-blocking request pipeline
- Proper lifecycle management
- Error handling and logging
- Graceful shutdown
- Resource cleanup

---

### Rule 2: Use Hangfire for Job Queues

**Priority**: High

**Description**: Use Hangfire for job queues, retries, and job monitoring.

**Incorrect**:

```csharp
// Manual job queue implementation
public class JobQueue
{
    private readonly Queue<Func<Task>> _jobs = new();
    
    public void Enqueue(Func<Task> job)
    {
        _jobs.Enqueue(job);
        Task.Run(async () => await ProcessJobAsync()); // No persistence, no retry
    }
}
```

**Correct**:

```csharp
// Hangfire configuration
builder.Services.AddHangfire(config =>
{
    config.UseSqlServerStorage(builder.Configuration.GetConnectionString("DefaultConnection"));
    config.UseSimpleAssemblyNameTypeSerializer();
    config.UseRecommendedSerializerSettings();
});

builder.Services.AddHangfireServer(options =>
{
    options.WorkerCount = Environment.ProcessorCount * 5;
    options.Queues = new[] { "default", "critical", "low" };
});

var app = builder.Build();

app.UseHangfireDashboard("/hangfire", new DashboardOptions
{
    Authorization = new[] { new HangfireAuthorizationFilter() }
});

// Enqueue jobs
public class OrderService
{
    private readonly IBackgroundJobClient _backgroundJob;

    public OrderService(IBackgroundJobClient backgroundJob)
    {
        _backgroundJob = backgroundJob;
    }

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        var order = await _repository.CreateAsync(request);
        
        // Enqueue background job
        _backgroundJob.Enqueue<IEmailService>(x => 
            x.SendOrderConfirmationAsync(order.Id));
        
        // Schedule delayed job
        _backgroundJob.Schedule<IInventoryService>(x => 
            x.UpdateInventoryAsync(order.Items),
            TimeSpan.FromMinutes(5));
        
        // Recurring job
        RecurringJob.AddOrUpdate<IOrderService>(
            "process-pending-orders",
            x => x.ProcessPendingOrdersAsync(),
            Cron.Minutely);

        return order;
    }
}

// Job with retry
[AutomaticRetry(Attempts = 3, DelaysInSeconds = new[] { 60, 120, 300 })]
public class EmailService : IEmailService
{
    public async Task SendOrderConfirmationAsync(int orderId)
    {
        // Email sending logic with automatic retry
    }
}
```

**Why**:
- Persistent job storage
- Automatic retries
- Job monitoring dashboard
- Job scheduling
- Better reliability

---

### Rule 3: Use Quartz.NET for Complex Scheduling

**Priority**: Medium

**Description**: Use Quartz.NET for complex scheduling requirements with cron expressions.

**Incorrect**:

```csharp
// Manual scheduling with Timer
var timer = new Timer(async _ =>
{
    await DoScheduledWorkAsync();
}, null, TimeSpan.Zero, TimeSpan.FromHours(1)); // Fixed interval only
```

**Correct**:

```csharp
// Quartz.NET configuration
builder.Services.AddQuartz(q =>
{
    q.UseMicrosoftDependencyInjection();
    
    // Simple job
    var jobKey = new JobKey("DailyReportJob");
    q.AddJob<DailyReportJob>(opts => opts.WithIdentity(jobKey));
    q.AddTrigger(opts => opts
        .ForJob(jobKey)
        .WithIdentity("DailyReportTrigger")
        .WithCronSchedule("0 0 9 * * ?")); // 9 AM daily
    
    // Job with data
    var cleanupJobKey = new JobKey("CleanupJob");
    q.AddJob<CleanupJob>(opts => opts.WithIdentity(cleanupJobKey));
    q.AddTrigger(opts => opts
        .ForJob(cleanupJobKey)
        .WithIdentity("CleanupTrigger")
        .WithCronSchedule("0 0 2 * * ?") // 2 AM daily
        .UsingJobData("retentionDays", 30));
});

builder.Services.AddQuartzHostedService(q => q.WaitForJobsToComplete = true);

// Job implementation
[DisallowConcurrentExecution]
public class DailyReportJob : IJob
{
    private readonly ILogger<DailyReportJob> _logger;
    private readonly IReportService _reportService;

    public DailyReportJob(
        ILogger<DailyReportJob> logger,
        IReportService reportService)
    {
        _logger = logger;
        _reportService = reportService;
    }

    public async Task Execute(IJobExecutionContext context)
    {
        _logger.LogInformation("Starting daily report generation");
        
        try
        {
            var report = await _reportService.GenerateDailyReportAsync();
            await _reportService.SendReportAsync(report);
            
            _logger.LogInformation("Daily report generated and sent successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to generate daily report");
            throw; // Quartz will retry based on configuration
        }
    }
}
```

**Why**:
- Complex scheduling with cron
- Job persistence
- Clustering support
- Job state management
- Professional scheduling

---

### Rule 4: Implement Proper Error Handling and Retries

**Priority**: High

**Description**: Always implement error handling and retry logic for background jobs.

**Incorrect**:

```csharp
// No error handling
public class EmailJob
{
    public async Task SendEmailAsync(int orderId)
    {
        await _emailService.SendAsync(orderId); // Fails silently
    }
}

// No retry logic
public class ProcessOrderJob
{
    public async Task ProcessAsync(int orderId)
    {
        try
        {
            await _orderService.ProcessAsync(orderId);
        }
        catch (Exception)
        {
            // Job fails permanently
        }
    }
}
```

**Correct**:

```csharp
// Job with retry and error handling
public class EmailJob
{
    private readonly IEmailService _emailService;
    private readonly ILogger<EmailJob> _logger;
    private readonly IOrderRepository _orderRepository;

    public async Task SendOrderConfirmationAsync(int orderId)
    {
        var maxRetries = 3;
        var retryCount = 0;

        while (retryCount < maxRetries)
        {
            try
            {
                await _emailService.SendOrderConfirmationAsync(orderId);
                _logger.LogInformation("Order confirmation sent for order {OrderId}", orderId);
                return;
            }
            catch (TransientException ex) when (retryCount < maxRetries - 1)
            {
                retryCount++;
                var delay = TimeSpan.FromSeconds(Math.Pow(2, retryCount)); // Exponential backoff
                _logger.LogWarning(
                    ex,
                    "Failed to send email for order {OrderId}. Retry {RetryCount}/{MaxRetries} after {Delay}s",
                    orderId, retryCount, maxRetries, delay.TotalSeconds);
                
                await Task.Delay(delay);
            }
            catch (Exception ex)
            {
                _logger.LogError(
                    ex,
                    "Permanent failure sending email for order {OrderId}",
                    orderId);
                
                // Mark order for manual review
                await _orderRepository.MarkEmailFailedAsync(orderId);
                throw;
            }
        }

        throw new Exception($"Failed to send email after {maxRetries} retries");
    }
}

// With Hangfire automatic retry
[AutomaticRetry(Attempts = 5, DelaysInSeconds = new[] { 60, 120, 300, 600, 1800 })]
public class ProcessOrderJob
{
    public async Task ProcessAsync(int orderId)
    {
        try
        {
            await _orderService.ProcessAsync(orderId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process order {OrderId}", orderId);
            throw; // Hangfire will retry automatically
        }
    }
}
```

**Why**:
- Handles transient failures
- Prevents job loss
- Exponential backoff
- Better reliability
- Production-ready

---

### Rule 5: Use Scoped Services in Background Jobs

**Priority**: High

**Description**: Create scopes when using scoped services in background jobs.

**Incorrect**:

```csharp
// Using scoped service directly - won't work
public class OrderProcessingService : BackgroundService
{
    private readonly IOrderRepository _repository; // Scoped service injected into singleton

    public OrderProcessingService(IOrderRepository repository)
    {
        _repository = repository; // Error: scoped service in singleton
    }
}
```

**Correct**:

```csharp
// Create scope for scoped services
public class OrderProcessingService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<OrderProcessingService> _logger;

    public OrderProcessingService(
        IServiceProvider serviceProvider,
        ILogger<OrderProcessingService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
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

// Hangfire job with scope
public class EmailJob
{
    private readonly IServiceProvider _serviceProvider;

    public async Task SendEmailAsync(int orderId)
    {
        using var scope = _serviceProvider.CreateScope();
        var emailService = scope.ServiceProvider.GetRequiredService<IEmailService>();
        await emailService.SendAsync(orderId);
    }
}
```

**Why**:
- Proper service lifetime management
- Prevents memory leaks
- Correct DI usage
- Essential for EF Core DbContext
- Best practice

---

### Rule 6: Monitor Background Jobs

**Priority**: Medium

**Description**: Implement monitoring and logging for background jobs.

**Correct**:

```csharp
// Instrumented background job
public class OrderProcessingJob
{
    private readonly IOrderService _orderService;
    private readonly ILogger<OrderProcessingJob> _logger;
    private readonly IMetrics _metrics;

    public async Task ProcessOrderAsync(int orderId)
    {
        using var activity = ActivitySource.StartActivity("ProcessOrder");
        activity?.SetTag("order.id", orderId);

        var stopwatch = Stopwatch.StartNew();
        
        try
        {
            _logger.LogInformation("Starting order processing for {OrderId}", orderId);
            
            await _orderService.ProcessAsync(orderId);
            
            stopwatch.Stop();
            _metrics.RecordProcessingTime(stopwatch.ElapsedMilliseconds);
            _metrics.IncrementProcessedOrders();
            
            _logger.LogInformation(
                "Order {OrderId} processed successfully in {Duration}ms",
                orderId,
                stopwatch.ElapsedMilliseconds);
            
            activity?.SetStatus(ActivityStatusCode.Ok);
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _metrics.IncrementFailedOrders();
            
            _logger.LogError(
                ex,
                "Failed to process order {OrderId} after {Duration}ms",
                orderId,
                stopwatch.ElapsedMilliseconds);
            
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.RecordException(ex);
            throw;
        }
    }
}
```

**Why**:
- Visibility into job execution
- Performance monitoring
- Error tracking
- Better debugging
- Production observability

---

## Integration Example

Complete background jobs setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// Hosted services
builder.Services.AddHostedService<OrderProcessingService>();
builder.Services.AddHostedService<CleanupService>();

// Hangfire
builder.Services.AddHangfire(config =>
{
    config.UseSqlServerStorage(builder.Configuration.GetConnectionString("DefaultConnection"));
});
builder.Services.AddHangfireServer();

// Quartz.NET
builder.Services.AddQuartz(q =>
{
    q.UseMicrosoftDependencyInjection();
    // Configure jobs
});
builder.Services.AddQuartzHostedService();

var app = builder.Build();

app.UseHangfireDashboard("/hangfire");
app.MapControllers();

app.Run();
```

## Checklist

- [ ] Hosted services for simple background tasks
- [ ] Hangfire for job queues (if needed)
- [ ] Quartz.NET for complex scheduling (if needed)
- [ ] Error handling and retries implemented
- [ ] Scoped services used correctly
- [ ] Jobs are monitored and logged
- [ ] Graceful shutdown handled
- [ ] Job persistence configured

## References

- [Background Tasks](https://docs.microsoft.com/aspnet/core/fundamentals/host/hosted-services)
- [Hangfire Documentation](https://docs.hangfire.io/)
- [Quartz.NET Documentation](https://www.quartz-scheduler.net/)

## Changelog

### v1.0.0
- Initial release
- 6 core rules for background jobs
