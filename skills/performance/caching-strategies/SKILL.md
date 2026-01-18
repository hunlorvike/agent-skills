---
name: caching-strategies
description: Best practices for implementing caching in ASP.NET Core including in-memory caching, distributed caching with Redis, response caching, and cache invalidation strategies.
version: 1.0.0
priority: high
categories:
  - performance
  - caching
use_when:
  - "When implementing caching to improve performance"
  - "When using Redis or distributed cache"
  - "When caching API responses"
  - "When optimizing database queries with cache"
  - "When implementing cache invalidation"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.Extensions.Caching.Memory"
  - "Microsoft.Extensions.Caching.StackExchangeRedis (optional)"
related_skills:
  - efcore-best-practices
  - webapi-best-practices
  - structured-logging
---

# Caching Strategies Best Practices

## Overview

This skill covers comprehensive caching strategies in ASP.NET Core. Proper caching can dramatically improve application performance by reducing database load and response times. This skill addresses:

- In-memory caching patterns
- Distributed caching with Redis
- Response caching middleware
- Cache invalidation strategies
- Cache key design
- Cache expiration policies

## Rules

### Rule 1: Use Appropriate Caching Strategy

**Priority**: High

**Description**: Choose the right caching strategy based on your requirements: in-memory for single server, distributed for multiple servers.

**Incorrect**:

```csharp
// No caching - hits database every time
[HttpGet("products/{id}")]
public async Task<ActionResult<ProductDto>> GetProduct(int id)
{
    var product = await _context.Products.FindAsync(id); // Database query every time
    return Ok(product);
}

// Using in-memory cache in multi-server scenario
public class ProductService
{
    private readonly IMemoryCache _cache; // Won't work across servers
    
    public async Task<Product> GetProductAsync(int id)
    {
        return await _cache.GetOrCreateAsync($"product-{id}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            return await _repository.GetByIdAsync(id);
        });
    }
}
```

**Correct**:

```csharp
// In-memory cache for single server
builder.Services.AddMemoryCache();

public class ProductService
{
    private readonly IMemoryCache _cache;
    private readonly IProductRepository _repository;

    public ProductService(IMemoryCache cache, IProductRepository repository)
    {
        _cache = cache;
        _repository = repository;
    }

    public async Task<ProductDto?> GetProductAsync(int id, CancellationToken ct = default)
    {
        var cacheKey = $"product:{id}";
        
        if (_cache.TryGetValue(cacheKey, out ProductDto? cachedProduct))
        {
            return cachedProduct;
        }

        var product = await _repository.GetByIdAsync(id, ct);
        if (product == null)
            return null;

        var dto = _mapper.Map<ProductDto>(product);
        
        var cacheOptions = new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10),
            SlidingExpiration = TimeSpan.FromMinutes(5),
            Priority = CacheItemPriority.Normal
        };

        _cache.Set(cacheKey, dto, cacheOptions);
        return dto;
    }
}

// Distributed cache for multi-server scenarios
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "MyApp:";
});

public class ProductService
{
    private readonly IDistributedCache _cache;
    private readonly IProductRepository _repository;

    public ProductService(IDistributedCache cache, IProductRepository repository)
    {
        _cache = cache;
        _repository = repository;
    }

    public async Task<ProductDto?> GetProductAsync(int id, CancellationToken ct = default)
    {
        var cacheKey = $"product:{id}";
        var cachedJson = await _cache.GetStringAsync(cacheKey, ct);
        
        if (cachedJson != null)
        {
            return JsonSerializer.Deserialize<ProductDto>(cachedJson);
        }

        var product = await _repository.GetByIdAsync(id, ct);
        if (product == null)
            return null;

        var dto = _mapper.Map<ProductDto>(product);
        var json = JsonSerializer.Serialize(dto);
        
        var cacheOptions = new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10),
            SlidingExpiration = TimeSpan.FromMinutes(5)
        };

        await _cache.SetStringAsync(cacheKey, json, cacheOptions, ct);
        return dto;
    }
}
```

**Why**:
- In-memory cache is fast but not shared
- Distributed cache works across servers
- Choose based on deployment architecture
- Significant performance improvement

---

### Rule 2: Design Effective Cache Keys

**Priority**: High

**Description**: Use consistent, hierarchical cache key naming to avoid collisions and enable invalidation.

**Incorrect**:

```csharp
// Poor cache key design
var key1 = $"product{id}"; // No separator, collision risk
var key2 = $"Product-{id}"; // Inconsistent casing
var key3 = $"{id}"; // Too generic, collisions
var key4 = $"user_{userId}_order_{orderId}_item_{itemId}"; // Too long, hard to invalidate
```

**Correct**:

```csharp
// Hierarchical cache key design
public static class CacheKeys
{
    public const string ProductPrefix = "products";
    public const string OrderPrefix = "orders";
    public const string UserPrefix = "users";
    
    public static string Product(int id) => $"{ProductPrefix}:{id}";
    public static string ProductList(string? search = null) => 
        search == null 
            ? $"{ProductPrefix}:list" 
            : $"{ProductPrefix}:list:search:{search}";
    
    public static string Order(int id) => $"{OrderPrefix}:{id}";
    public static string UserOrders(int userId) => $"{UserPrefix}:{userId}:orders";
    
    // Pattern for invalidation
    public static string ProductPattern() => $"{ProductPrefix}:*";
}

// Usage
public async Task<ProductDto?> GetProductAsync(int id)
{
    var cacheKey = CacheKeys.Product(id);
    // ...
}

// Invalidation by pattern
public async Task InvalidateProductCacheAsync(int productId)
{
    // Remove specific product
    await _cache.RemoveAsync(CacheKeys.Product(productId));
    
    // Remove product list (if using Redis with pattern matching)
    // await _cache.RemoveByPatternAsync(CacheKeys.ProductPattern());
}
```

**Why**:
- Prevents key collisions
- Enables pattern-based invalidation
- Consistent naming convention
- Easier debugging
- Better cache management

---

### Rule 3: Implement Cache-Aside Pattern

**Priority**: High

**Description**: Use cache-aside pattern: check cache first, if miss then load from source and populate cache.

**Incorrect**:

```csharp
// Write-through - always writes to both cache and database
public async Task<Product> UpdateProductAsync(int id, UpdateProductRequest request)
{
    var product = await _repository.UpdateAsync(id, request);
    await _cache.SetAsync($"product:{id}", product); // Always updates cache
    return product;
}

// Cache stampede - multiple requests miss cache simultaneously
public async Task<Product> GetProductAsync(int id)
{
    if (!_cache.TryGetValue($"product:{id}", out Product product))
    {
        // Multiple requests can hit database simultaneously
        product = await _repository.GetByIdAsync(id);
        _cache.Set($"product:{id}", product);
    }
    return product;
}
```

**Correct**:

```csharp
// Cache-aside pattern with locking
public class ProductService
{
    private readonly IDistributedCache _cache;
    private readonly IProductRepository _repository;
    private readonly SemaphoreSlim _semaphore = new(1, 1);

    public async Task<ProductDto?> GetProductAsync(int id, CancellationToken ct = default)
    {
        var cacheKey = CacheKeys.Product(id);
        var cachedJson = await _cache.GetStringAsync(cacheKey, ct);
        
        if (cachedJson != null)
        {
            return JsonSerializer.Deserialize<ProductDto>(cachedJson);
        }

        // Lock to prevent cache stampede
        await _semaphore.WaitAsync(ct);
        try
        {
            // Double-check after acquiring lock
            cachedJson = await _cache.GetStringAsync(cacheKey, ct);
            if (cachedJson != null)
            {
                return JsonSerializer.Deserialize<ProductDto>(cachedJson);
            }

            // Load from database
            var product = await _repository.GetByIdAsync(id, ct);
            if (product == null)
                return null;

            var dto = _mapper.Map<ProductDto>(product);
            var json = JsonSerializer.Serialize(dto);
            
            var cacheOptions = new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10)
            };

            await _cache.SetStringAsync(cacheKey, json, cacheOptions, ct);
            return dto;
        }
        finally
        {
            _semaphore.Release();
        }
    }

    public async Task<ProductDto> UpdateProductAsync(int id, UpdateProductRequest request)
    {
        // Update database
        var product = await _repository.UpdateAsync(id, request);
        var dto = _mapper.Map<ProductDto>(product);
        
        // Invalidate cache (cache-aside: write to DB, invalidate cache)
        var cacheKey = CacheKeys.Product(id);
        await _cache.RemoveAsync(cacheKey);
        
        // Optionally: warm cache with new data
        var json = JsonSerializer.Serialize(dto);
        await _cache.SetStringAsync(cacheKey, json, new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10)
        });
        
        return dto;
    }
}
```

**Why**:
- Prevents cache stampede
- Reduces database load
- Standard caching pattern
- Better performance
- Handles concurrent requests

---

### Rule 4: Use Response Caching for Static Data

**Priority**: Medium

**Description**: Use HTTP response caching for data that doesn't change frequently.

**Incorrect**:

```csharp
// No response caching
[HttpGet("products")]
public async Task<ActionResult<List<ProductDto>>> GetProducts()
{
    var products = await _service.GetAllAsync();
    return Ok(products); // No cache headers
}
```

**Correct**:

```csharp
// Response caching middleware
builder.Services.AddResponseCaching();
builder.Services.AddControllers(options =>
{
    options.CacheProfiles.Add("Default30", new CacheProfile
    {
        Duration = 30,
        VaryByQueryKeys = new[] { "search", "page", "pageSize" }
    });
    
    options.CacheProfiles.Add("Static60", new CacheProfile
    {
        Duration = 60,
        Location = ResponseCacheLocation.Any
    });
});

var app = builder.Build();
app.UseResponseCaching();
app.Use(async (context, next) =>
{
    context.Response.GetTypedHeaders().CacheControl = new Microsoft.Net.Http.Headers.CacheControlHeaderValue
    {
        Public = true,
        MaxAge = TimeSpan.FromSeconds(30)
    };
    await next();
});

// Use in controller
[HttpGet("products")]
[ResponseCache(Duration = 30, VaryByQueryKeys = new[] { "search", "page" })]
public async Task<ActionResult<List<ProductDto>>> GetProducts([FromQuery] string? search)
{
    var products = await _service.GetAllAsync(search);
    return Ok(products);
}

// Or use cache profile
[HttpGet("categories")]
[ResponseCache(CacheProfileName = "Static60")]
public async Task<ActionResult<List<CategoryDto>>> GetCategories()
{
    var categories = await _service.GetCategoriesAsync();
    return Ok(categories);
}
```

**Why**:
- Reduces server load
- Faster response times
- HTTP standard caching
- Browser/CDN caching
- Better scalability

---

### Rule 5: Implement Cache Invalidation Strategy

**Priority**: High

**Description**: Have a clear strategy for invalidating cache when data changes.

**Incorrect**:

```csharp
// No cache invalidation
public async Task<Product> UpdateProductAsync(int id, UpdateProductRequest request)
{
    var product = await _repository.UpdateAsync(id, request);
    // Cache still has old data!
    return product;
}

// Invalidating everything
public async Task<Product> UpdateProductAsync(int id, UpdateProductRequest request)
{
    var product = await _repository.UpdateAsync(id, request);
    await _cache.RemoveAsync("*"); // Too aggressive, clears everything
    return product;
}
```

**Correct**:

```csharp
// Targeted cache invalidation
public class ProductService
{
    private readonly IDistributedCache _cache;
    private readonly IProductRepository _repository;

    public async Task<ProductDto> UpdateProductAsync(int id, UpdateProductRequest request)
    {
        // Update database
        var product = await _repository.UpdateAsync(id, request);
        var dto = _mapper.Map<ProductDto>(product);
        
        // Invalidate related cache entries
        await InvalidateProductCacheAsync(id);
        
        return dto;
    }

    private async Task InvalidateProductCacheAsync(int productId)
    {
        // Remove specific product
        await _cache.RemoveAsync(CacheKeys.Product(productId));
        
        // Remove product lists (they may contain this product)
        // Note: This is simplified - in production, use Redis SCAN or maintain list keys
        var listKeys = new[]
        {
            CacheKeys.ProductList(),
            CacheKeys.ProductList(""),
            // Add other search variations if needed
        };
        
        foreach (var key in listKeys)
        {
            await _cache.RemoveAsync(key);
        }
    }

    public async Task<ProductDto> DeleteProductAsync(int id)
    {
        await _repository.DeleteAsync(id);
        await InvalidateProductCacheAsync(id);
        // Also invalidate any dependent caches
        return null;
    }
}

// Or use cache tags (Redis with RedLock or similar)
public class CacheTagService
{
    private readonly IDistributedCache _cache;

    public async Task InvalidateByTagAsync(string tag)
    {
        // Get all keys with this tag
        var keys = await GetKeysByTagAsync(tag);
        foreach (var key in keys)
        {
            await _cache.RemoveAsync(key);
        }
    }
}
```

**Why**:
- Prevents stale data
- Maintains data consistency
- Targeted invalidation is efficient
- Better user experience
- Critical for data integrity

---

### Rule 6: Set Appropriate Expiration Policies

**Priority**: High

**Description**: Use appropriate expiration policies based on data volatility.

**Incorrect**:

```csharp
// Same expiration for all data
var options = new MemoryCacheEntryOptions
{
    AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5) // Too short for static data, too long for dynamic
};

// No expiration - memory leak risk
_cache.Set(key, value); // Never expires
```

**Correct**:

```csharp
// Different expiration for different data types
public class CacheOptionsFactory
{
    public static MemoryCacheEntryOptions ForStaticData()
    {
        return new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1),
            Priority = CacheItemPriority.High
        };
    }

    public static MemoryCacheEntryOptions ForDynamicData()
    {
        return new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5),
            SlidingExpiration = TimeSpan.FromMinutes(2), // Extend if accessed
            Priority = CacheItemPriority.Normal
        };
    }

    public static MemoryCacheEntryOptions ForUserData()
    {
        return new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(15),
            SlidingExpiration = TimeSpan.FromMinutes(5),
            Priority = CacheItemPriority.Normal
        };
    }

    public static MemoryCacheEntryOptions ForFrequentlyChangingData()
    {
        return new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(30),
            Priority = CacheItemPriority.Low
        };
    }
}

// Usage
public async Task<CategoryDto> GetCategoryAsync(int id)
{
    var cacheKey = CacheKeys.Category(id);
    if (_cache.TryGetValue(cacheKey, out CategoryDto? category))
        return category;

    category = await _repository.GetCategoryAsync(id);
    _cache.Set(cacheKey, category, CacheOptionsFactory.ForStaticData());
    return category;
}

public async Task<ProductDto> GetProductAsync(int id)
{
    var cacheKey = CacheKeys.Product(id);
    if (_cache.TryGetValue(cacheKey, out ProductDto? product))
        return product;

    product = await _repository.GetProductAsync(id);
    _cache.Set(cacheKey, product, CacheOptionsFactory.ForDynamicData());
    return product;
}
```

**Why**:
- Optimizes cache hit rates
- Prevents stale data
- Manages memory efficiently
- Data-appropriate expiration
- Better performance

---

### Rule 7: Monitor Cache Performance

**Priority**: Medium

**Description**: Monitor cache hit rates and performance to optimize caching strategy.

**Correct**:

```csharp
// Cache metrics
public class CacheMetrics
{
    private long _hits = 0;
    private long _misses = 0;

    public void RecordHit() => Interlocked.Increment(ref _hits);
    public void RecordMiss() => Interlocked.Increment(ref _misses);

    public double HitRate => _hits + _misses == 0 
        ? 0 
        : (double)_hits / (_hits + _misses) * 100;
}

// Instrumented cache service
public class InstrumentedProductService
{
    private readonly IDistributedCache _cache;
    private readonly CacheMetrics _metrics;
    private readonly ILogger<InstrumentedProductService> _logger;

    public async Task<ProductDto?> GetProductAsync(int id, CancellationToken ct = default)
    {
        var cacheKey = CacheKeys.Product(id);
        var cachedJson = await _cache.GetStringAsync(cacheKey, ct);
        
        if (cachedJson != null)
        {
            _metrics.RecordHit();
            _logger.LogDebug("Cache hit for {CacheKey}", cacheKey);
            return JsonSerializer.Deserialize<ProductDto>(cachedJson);
        }

        _metrics.RecordMiss();
        _logger.LogDebug("Cache miss for {CacheKey}", cacheKey);

        var product = await _repository.GetByIdAsync(id, ct);
        if (product == null)
            return null;

        var dto = _mapper.Map<ProductDto>(product);
        var json = JsonSerializer.Serialize(dto);
        
        await _cache.SetStringAsync(cacheKey, json, new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10)
        }, ct);

        // Log metrics periodically
        if (_metrics.HitRate > 0)
        {
            _logger.LogInformation(
                "Cache performance - Hits: {Hits}, Misses: {Misses}, Hit Rate: {HitRate:F2}%",
                _metrics.Hits, _metrics.Misses, _metrics.HitRate);
        }

        return dto;
    }
}
```

**Why**:
- Identifies cache effectiveness
- Optimizes cache configuration
- Detects performance issues
- Data-driven decisions
- Better resource utilization

---

## Integration Example

Complete caching setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// In-memory cache
builder.Services.AddMemoryCache();

// Or distributed cache
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "MyApp:";
});

// Response caching
builder.Services.AddResponseCaching();
builder.Services.AddControllers(options =>
{
    options.CacheProfiles.Add("Default30", new CacheProfile
    {
        Duration = 30
    });
});

var app = builder.Build();

app.UseResponseCaching();
app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

## Checklist

- [ ] Appropriate caching strategy chosen (in-memory vs distributed)
- [ ] Consistent cache key naming
- [ ] Cache-aside pattern implemented
- [ ] Response caching for static data
- [ ] Cache invalidation strategy defined
- [ ] Appropriate expiration policies set
- [ ] Cache performance monitored
- [ ] Cache stampede prevention

## References

- [Caching in ASP.NET Core](https://docs.microsoft.com/aspnet/core/performance/caching/)
- [Distributed Caching](https://docs.microsoft.com/aspnet/core/performance/caching/distributed)
- [Response Caching](https://docs.microsoft.com/aspnet/core/performance/caching/response)

## Changelog

### v1.0.0
- Initial release
- 7 core rules for caching strategies
