---
name: distributed-tracing
description: Best practices for implementing distributed tracing in ASP.NET Core using OpenTelemetry, Application Insights, or other tracing systems to track requests across services.
version: 1.0.0
priority: high
categories:
  - observability
  - tracing
  - monitoring
use_when:
  - "When building microservices"
  - "When debugging distributed systems"
  - "When implementing request correlation"
  - "When monitoring multi-service applications"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "OpenTelemetry or Application Insights"
related_skills:
  - structured-logging
  - health-checks
---

# Distributed Tracing Best Practices

## Overview

This skill covers implementing distributed tracing in ASP.NET Core to track requests across multiple services, essential for debugging and monitoring microservices architectures.

## Rules

### Rule 1: Use OpenTelemetry for Tracing

**Priority**: High

**Description**: Use OpenTelemetry for vendor-neutral distributed tracing.

**Incorrect**:

```csharp
// No tracing configured
var app = builder.Build();
app.MapControllers();
app.Run();
```

**Correct**:

```csharp
// OpenTelemetry configuration
builder.Services.AddOpenTelemetry()
    .WithTracing(builder => builder
        .AddAspNetCoreInstrumentation(options =>
        {
            options.RecordException = true;
            options.EnrichWithHttpRequest = (activity, request) =>
            {
                activity.SetTag("http.user_agent", request.Headers.UserAgent.ToString());
            };
        })
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddSource("MyApp") // Custom activity source
        .AddJaegerExporter() // Or Application Insights, Zipkin, etc.
    );

// Custom activities
public class OrderService
{
    private static readonly ActivitySource ActivitySource = new("MyApp.Orders");

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        using var activity = ActivitySource.StartActivity("CreateOrder");
        activity?.SetTag("order.customer_id", request.CustomerId);
        activity?.SetTag("order.item_count", request.Items.Count);

        try
        {
            var order = await ProcessOrderAsync(request);
            activity?.SetStatus(ActivityStatusCode.Ok);
            return order;
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.RecordException(ex);
            throw;
        }
    }
}
```

**Why**:
- Vendor-neutral tracing
- Works with multiple backends
- Industry standard
- Rich instrumentation

---

### Rule 2: Propagate Trace Context

**Priority**: High

**Description**: Ensure trace context is propagated across service boundaries.

**Correct**:

```csharp
// HTTP client with trace propagation
builder.Services.AddHttpClient<IExternalApiClient>(client =>
{
    client.BaseAddress = new Uri("https://api.example.com");
})
.AddHttpClientInstrumentation(); // Automatic trace propagation

// Manual trace context propagation
public class ExternalApiService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<ExternalApiService> _logger;

    public async Task<string> CallExternalApiAsync(string endpoint)
    {
        using var activity = ActivitySource.StartActivity("CallExternalApi");
        
        var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
        
        // Propagate trace context
        Activity.Current?.Context.Inject(
            request.Headers,
            (headers, key, value) => headers.Add(key, value));

        var response = await _httpClient.SendAsync(request);
        return await response.Content.ReadAsStringAsync();
    }
}
```

**Why**:
- Maintains trace continuity
- Tracks requests across services
- Essential for distributed systems
- Better debugging

---

### Rule 3: Use Application Insights (Azure)

**Priority**: Medium

**Description**: Configure Application Insights for Azure-hosted applications.

**Correct**:

```csharp
// Application Insights
builder.Services.AddApplicationInsightsTelemetry(options =>
{
    options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
    options.EnableAdaptiveSampling = true;
    options.EnablePerformanceCounterCollectionModule = true;
});

// Or with OpenTelemetry
builder.Services.AddOpenTelemetry()
    .UseAzureMonitor(options =>
    {
        options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
    });

// Custom telemetry
public class OrderService
{
    private readonly TelemetryClient _telemetryClient;

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        using var operation = _telemetryClient.StartOperation<DependencyTelemetry>("CreateOrder");
        operation.Telemetry.Type = "OrderService";
        
        try
        {
            var order = await ProcessOrderAsync(request);
            _telemetryClient.TrackEvent("OrderCreated", new Dictionary<string, string>
            {
                ["OrderId"] = order.Id.ToString(),
                ["CustomerId"] = request.CustomerId.ToString()
            });
            return order;
        }
        catch (Exception ex)
        {
            _telemetryClient.TrackException(ex);
            throw;
        }
    }
}
```

**Why**:
- Integrated with Azure services
- Rich monitoring capabilities
- Easy to set up
- Production-ready

---

## Integration Example

Complete tracing setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// OpenTelemetry
builder.Services.AddOpenTelemetry()
    .WithTracing(builder => builder
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddJaegerExporter());

var app = builder.Build();

app.Use(async (context, next) =>
{
    // Add custom trace attributes
    Activity.Current?.SetTag("http.route", context.Request.Path);
    await next();
});

app.MapControllers();
app.Run();
```

## Checklist

- [ ] OpenTelemetry configured
- [ ] Trace context propagated
- [ ] Custom activities created
- [ ] Exceptions recorded
- [ ] Exporter configured
- [ ] Sampling configured
- [ ] Custom tags added

## References

- [OpenTelemetry](https://opentelemetry.io/)
- [Application Insights](https://docs.microsoft.com/azure/azure-monitor/app/app-insights-overview)

## Changelog

### v1.0.0
- Initial release
- 3 core rules for distributed tracing
