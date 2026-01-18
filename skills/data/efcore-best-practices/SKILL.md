---
name: efcore-best-practices
description: Best practices for Entity Framework Core including query optimization, avoiding N+1 problems, proper tracking usage, and performance tuning.
version: 1.0.0
priority: critical
categories:
  - data
  - performance
  - efcore
use_when:
  - "When writing LINQ queries with EF Core"
  - "When experiencing slow database queries"
  - "When reviewing data access code"
  - "When designing DbContext and entities"
  - "When optimizing application performance"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.EntityFrameworkCore 8.0+"
related_skills:
  - repository-unitofwork
  - database-migrations
  - structured-logging
---

# Entity Framework Core Best Practices

## Overview

This skill covers critical best practices for using Entity Framework Core effectively. Poor EF Core usage is one of the most common causes of performance issues in ASP.NET applications. This skill helps you:

- Avoid N+1 query problems
- Use change tracking appropriately
- Optimize LINQ queries
- Configure entities properly
- Handle concurrency correctly

## Rules

### Rule 1: Avoid N+1 Query Problems

**Priority**: Critical

**Description**: The N+1 problem occurs when you execute 1 query to get N records, then N additional queries to get related data. Use eager loading, explicit loading, or projection to avoid this.

**Incorrect**:

```csharp
// N+1 Problem - 1 query for orders + N queries for items
public async Task<List<OrderDto>> GetOrdersWithItemsAsync()
{
    var orders = await _context.Orders.ToListAsync();
    
    var result = new List<OrderDto>();
    foreach (var order in orders)
    {
        // Each access triggers a separate query (lazy loading)
        var items = order.Items.ToList(); // N additional queries!
        result.Add(new OrderDto
        {
            Id = order.Id,
            Items = items.Select(i => new ItemDto { ... }).ToList()
        });
    }
    return result;
}

// Even worse - querying in a loop
public async Task<List<OrderDto>> GetOrdersAsync()
{
    var orderIds = await _context.Orders.Select(o => o.Id).ToListAsync();
    
    var result = new List<OrderDto>();
    foreach (var id in orderIds)
    {
        // Separate query for EACH order
        var order = await _context.Orders
            .Include(o => o.Items)
            .FirstOrDefaultAsync(o => o.Id == id);
        result.Add(MapToDto(order));
    }
    return result;
}
```

**Correct**:

```csharp
// Solution 1: Eager Loading with Include
public async Task<List<OrderDto>> GetOrdersWithItemsAsync()
{
    var orders = await _context.Orders
        .Include(o => o.Items)
        .Include(o => o.Customer)
        .AsNoTracking()
        .ToListAsync();
    
    return orders.Select(o => new OrderDto
    {
        Id = o.Id,
        CustomerName = o.Customer.Name,
        Items = o.Items.Select(i => new ItemDto
        {
            ProductId = i.ProductId,
            Quantity = i.Quantity
        }).ToList()
    }).ToList();
}

// Solution 2: Projection (Most Efficient)
public async Task<List<OrderDto>> GetOrdersWithItemsAsync()
{
    return await _context.Orders
        .Select(o => new OrderDto
        {
            Id = o.Id,
            CustomerName = o.Customer.Name,
            TotalAmount = o.Items.Sum(i => i.Quantity * i.UnitPrice),
            Items = o.Items.Select(i => new ItemDto
            {
                ProductId = i.ProductId,
                ProductName = i.Product.Name,
                Quantity = i.Quantity,
                UnitPrice = i.UnitPrice
            }).ToList()
        })
        .AsNoTracking()
        .ToListAsync();
}

// Solution 3: Split Query for complex includes
public async Task<List<Order>> GetOrdersAsync()
{
    return await _context.Orders
        .Include(o => o.Items)
            .ThenInclude(i => i.Product)
        .Include(o => o.Customer)
        .AsSplitQuery() // Splits into multiple queries to avoid cartesian explosion
        .AsNoTracking()
        .ToListAsync();
}
```

**Why**:
- N+1 queries cause severe performance degradation
- Each query has network latency and database overhead
- Can turn a simple page load into hundreds of queries
- Projection is often 10x+ faster than Include for read operations

---

### Rule 2: Use AsNoTracking for Read-Only Queries

**Priority**: High

**Description**: Disable change tracking for queries that don't need to update entities. This significantly improves memory usage and performance.

**Incorrect**:

```csharp
// Change tracking enabled by default - unnecessary overhead
public async Task<List<ProductDto>> GetProductsAsync()
{
    var products = await _context.Products.ToListAsync();
    return _mapper.Map<List<ProductDto>>(products);
}

public async Task<ProductDto?> GetProductAsync(int id)
{
    var product = await _context.Products
        .Include(p => p.Category)
        .FirstOrDefaultAsync(p => p.Id == id);
    
    // Just reading, but EF Core is tracking all these entities
    return _mapper.Map<ProductDto>(product);
}
```

**Correct**:

```csharp
// AsNoTracking for read-only operations
public async Task<List<ProductDto>> GetProductsAsync()
{
    var products = await _context.Products
        .AsNoTracking()
        .ToListAsync();
    
    return _mapper.Map<List<ProductDto>>(products);
}

public async Task<ProductDto?> GetProductAsync(int id)
{
    var product = await _context.Products
        .AsNoTracking()
        .Include(p => p.Category)
        .FirstOrDefaultAsync(p => p.Id == id);
    
    return _mapper.Map<ProductDto>(product);
}

// Configure at DbContext level for read-heavy scenarios
public class ReadOnlyDbContext : DbContext
{
    public ReadOnlyDbContext(DbContextOptions<ReadOnlyDbContext> options)
        : base(options)
    {
        ChangeTracker.QueryTrackingBehavior = QueryTrackingBehavior.NoTracking;
    }
}

// Or per query type
public async Task<List<ProductDto>> SearchProductsAsync(string search)
{
    return await _context.Products
        .AsNoTrackingWithIdentityResolution() // No tracking but resolves duplicates
        .Where(p => p.Name.Contains(search))
        .Select(p => new ProductDto { Id = p.Id, Name = p.Name })
        .ToListAsync();
}
```

**Why**:
- Change tracking adds memory overhead for each tracked entity
- Without tracking, EF Core skips snapshot creation
- Can reduce memory usage by 30-50% for large result sets
- Queries execute faster without tracking overhead

---

### Rule 3: Use Projection Instead of Loading Full Entities

**Priority**: High

**Description**: Select only the columns you need using projection. Loading full entities wastes memory and bandwidth.

**Incorrect**:

```csharp
// Loading entire entity when only needing a few fields
public async Task<List<string>> GetProductNamesAsync()
{
    var products = await _context.Products.ToListAsync();
    return products.Select(p => p.Name).ToList();
}

// Loading all columns for a dropdown
public async Task<List<SelectListItem>> GetCategoryDropdownAsync()
{
    var categories = await _context.Categories
        .Include(c => c.Products) // Unnecessary!
        .ToListAsync();
    
    return categories.Select(c => new SelectListItem
    {
        Value = c.Id.ToString(),
        Text = c.Name
    }).ToList();
}
```

**Correct**:

```csharp
// Project only needed columns
public async Task<List<string>> GetProductNamesAsync()
{
    return await _context.Products
        .Select(p => p.Name)
        .ToListAsync();
}

// Efficient dropdown query
public async Task<List<SelectListItem>> GetCategoryDropdownAsync()
{
    return await _context.Categories
        .OrderBy(c => c.Name)
        .Select(c => new SelectListItem
        {
            Value = c.Id.ToString(),
            Text = c.Name
        })
        .AsNoTracking()
        .ToListAsync();
}

// Complex projection with computed values
public async Task<List<OrderSummaryDto>> GetOrderSummariesAsync()
{
    return await _context.Orders
        .Select(o => new OrderSummaryDto
        {
            OrderId = o.Id,
            OrderNumber = o.OrderNumber,
            CustomerName = o.Customer.FirstName + " " + o.Customer.LastName,
            ItemCount = o.Items.Count,
            TotalAmount = o.Items.Sum(i => i.Quantity * i.UnitPrice),
            Status = o.Status.ToString()
        })
        .AsNoTracking()
        .ToListAsync();
}
```

**Why**:
- Reduces data transferred from database
- Lower memory consumption
- Faster serialization
- SQL query fetches only needed columns

---

### Rule 4: Use Compiled Queries for Hot Paths

**Priority**: Medium

**Description**: For frequently executed queries, use compiled queries to eliminate LINQ expression compilation overhead.

**Incorrect**:

```csharp
// Query is compiled every time it's executed
public async Task<Product?> GetProductBySkuAsync(string sku)
{
    return await _context.Products
        .FirstOrDefaultAsync(p => p.Sku == sku);
}
```

**Correct**:

```csharp
public class ProductRepository
{
    private readonly AppDbContext _context;
    
    // Compiled query - expression is compiled once
    private static readonly Func<AppDbContext, string, Task<Product?>> GetBySku =
        EF.CompileAsyncQuery((AppDbContext ctx, string sku) =>
            ctx.Products.FirstOrDefault(p => p.Sku == sku));
    
    private static readonly Func<AppDbContext, int, int, IAsyncEnumerable<Product>> GetPaged =
        EF.CompileAsyncQuery((AppDbContext ctx, int skip, int take) =>
            ctx.Products
                .OrderBy(p => p.Name)
                .Skip(skip)
                .Take(take));

    public ProductRepository(AppDbContext context)
    {
        _context = context;
    }

    public Task<Product?> GetProductBySkuAsync(string sku)
    {
        return GetBySku(_context, sku);
    }
    
    public async Task<List<Product>> GetPagedAsync(int page, int pageSize)
    {
        var products = new List<Product>();
        await foreach (var product in GetPaged(_context, (page - 1) * pageSize, pageSize))
        {
            products.Add(product);
        }
        return products;
    }
}
```

**Why**:
- Eliminates expression tree compilation on each call
- Can improve performance by 10-20% for simple queries
- Most beneficial for high-frequency queries
- Pre-compiled queries are cached

---

### Rule 5: Handle Pagination Correctly

**Priority**: High

**Description**: Always paginate large result sets. Never load all records into memory.

**Incorrect**:

```csharp
// Loading ALL records then paginating in memory
public async Task<PagedResult<ProductDto>> GetProductsAsync(int page, int pageSize)
{
    var allProducts = await _context.Products.ToListAsync(); // Dangerous!
    
    var pagedProducts = allProducts
        .Skip((page - 1) * pageSize)
        .Take(pageSize)
        .ToList();
    
    return new PagedResult<ProductDto>
    {
        Items = _mapper.Map<List<ProductDto>>(pagedProducts),
        TotalCount = allProducts.Count
    };
}
```

**Correct**:

```csharp
public async Task<PagedResult<ProductDto>> GetProductsAsync(
    int page, 
    int pageSize,
    CancellationToken cancellationToken = default)
{
    // Count and data in separate queries for efficiency
    var totalCount = await _context.Products.CountAsync(cancellationToken);
    
    var products = await _context.Products
        .AsNoTracking()
        .OrderBy(p => p.Name) // Always order for consistent paging
        .Skip((page - 1) * pageSize)
        .Take(pageSize)
        .Select(p => new ProductDto
        {
            Id = p.Id,
            Name = p.Name,
            Price = p.Price
        })
        .ToListAsync(cancellationToken);
    
    return new PagedResult<ProductDto>
    {
        Items = products,
        TotalCount = totalCount,
        Page = page,
        PageSize = pageSize,
        TotalPages = (int)Math.Ceiling(totalCount / (double)pageSize)
    };
}

// Using keyset pagination for better performance on large datasets
public async Task<List<ProductDto>> GetProductsAfterAsync(
    int lastId, 
    int pageSize,
    CancellationToken cancellationToken = default)
{
    return await _context.Products
        .AsNoTracking()
        .Where(p => p.Id > lastId)
        .OrderBy(p => p.Id)
        .Take(pageSize)
        .Select(p => new ProductDto { Id = p.Id, Name = p.Name })
        .ToListAsync(cancellationToken);
}
```

**Why**:
- Loading all records causes OutOfMemoryException on large tables
- Database pagination is extremely efficient
- Keyset pagination performs better than offset on large datasets
- Always include ORDER BY for deterministic results

---

### Rule 6: Configure Entities Properly with Fluent API

**Priority**: High

**Description**: Use Fluent API for entity configuration. Keep configurations organized and avoid mixing Data Annotations with Fluent API.

**Incorrect**:

```csharp
// Mixing approaches and missing important configurations
public class Order
{
    public int Id { get; set; }
    
    [Required]
    [MaxLength(50)]
    public string OrderNumber { get; set; }
    
    public decimal TotalAmount { get; set; } // No precision specified!
    
    public Customer Customer { get; set; } // No FK configured
    public ICollection<OrderItem> Items { get; set; } // No cascade config
}

public class AppDbContext : DbContext
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Minimal or missing configuration
    }
}
```

**Correct**:

```csharp
// Entity with minimal annotations
public class Order
{
    public int Id { get; set; }
    public string OrderNumber { get; set; } = string.Empty;
    public decimal TotalAmount { get; set; }
    public DateTime CreatedAt { get; set; }
    public int CustomerId { get; set; }
    
    public Customer Customer { get; set; } = null!;
    public ICollection<OrderItem> Items { get; set; } = new List<OrderItem>();
}

// Separate configuration class
public class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> builder)
    {
        builder.ToTable("Orders");
        
        builder.HasKey(o => o.Id);
        
        builder.Property(o => o.OrderNumber)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(o => o.TotalAmount)
            .HasPrecision(18, 2); // Important for decimals!
        
        builder.Property(o => o.CreatedAt)
            .HasDefaultValueSql("GETUTCDATE()");
        
        builder.HasIndex(o => o.OrderNumber)
            .IsUnique();
        
        builder.HasIndex(o => o.CreatedAt);
        
        builder.HasOne(o => o.Customer)
            .WithMany(c => c.Orders)
            .HasForeignKey(o => o.CustomerId)
            .OnDelete(DeleteBehavior.Restrict);
        
        builder.HasMany(o => o.Items)
            .WithOne(i => i.Order)
            .HasForeignKey(i => i.OrderId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

// DbContext with organized configuration
public class AppDbContext : DbContext
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Apply all configurations from assembly
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        
        // Global query filters
        modelBuilder.Entity<Order>()
            .HasQueryFilter(o => !o.IsDeleted);
    }
}
```

**Why**:
- Fluent API provides full configuration capabilities
- Separating configurations improves maintainability
- Explicit FK and navigation setup prevents surprises
- Decimal precision prevents data loss

---

### Rule 7: Use Transactions Appropriately

**Priority**: High

**Description**: Use transactions for operations that must succeed or fail together. Don't hold transactions longer than necessary.

**Incorrect**:

```csharp
// No transaction - partial failure possible
public async Task TransferFundsAsync(int fromId, int toId, decimal amount)
{
    var fromAccount = await _context.Accounts.FindAsync(fromId);
    var toAccount = await _context.Accounts.FindAsync(toId);
    
    fromAccount.Balance -= amount;
    await _context.SaveChangesAsync(); // First save
    
    // If this fails, fromAccount is already debited!
    toAccount.Balance += amount;
    await _context.SaveChangesAsync();
}

// Transaction held too long
public async Task ProcessOrderAsync(CreateOrderRequest request)
{
    using var transaction = await _context.Database.BeginTransactionAsync();
    
    var order = CreateOrder(request);
    await _context.SaveChangesAsync();
    
    // Slow external API call inside transaction - BAD!
    await _paymentService.ProcessPaymentAsync(order.Id);
    
    await _emailService.SendConfirmationAsync(order.Id); // Even worse
    
    await transaction.CommitAsync();
}
```

**Correct**:

```csharp
// Proper transaction usage
public async Task TransferFundsAsync(int fromId, int toId, decimal amount)
{
    await using var transaction = await _context.Database.BeginTransactionAsync();
    
    try
    {
        var fromAccount = await _context.Accounts.FindAsync(fromId)
            ?? throw new NotFoundException($"Account {fromId} not found");
        var toAccount = await _context.Accounts.FindAsync(toId)
            ?? throw new NotFoundException($"Account {toId} not found");
        
        if (fromAccount.Balance < amount)
            throw new InsufficientFundsException();
        
        fromAccount.Balance -= amount;
        toAccount.Balance += amount;
        
        await _context.SaveChangesAsync();
        await transaction.CommitAsync();
    }
    catch
    {
        await transaction.RollbackAsync();
        throw;
    }
}

// Keep transactions short - external calls outside
public async Task ProcessOrderAsync(CreateOrderRequest request)
{
    Order order;
    
    // Transaction only for database operations
    await using (var transaction = await _context.Database.BeginTransactionAsync())
    {
        order = CreateOrder(request);
        await _context.SaveChangesAsync();
        
        await UpdateInventory(order.Items);
        await _context.SaveChangesAsync();
        
        await transaction.CommitAsync();
    }
    
    // External calls AFTER transaction completes
    try
    {
        await _paymentService.ProcessPaymentAsync(order.Id);
        await _emailService.SendConfirmationAsync(order.Id);
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Post-order processing failed for {OrderId}", order.Id);
        // Handle compensation logic if needed
    }
}

// Using SaveChanges for implicit transaction
public async Task CreateOrderWithItemsAsync(Order order)
{
    // Single SaveChanges = implicit transaction
    _context.Orders.Add(order);
    await _context.SaveChangesAsync(); // All or nothing
}
```

**Why**:
- Ensures data consistency
- Prevents partial updates
- Short transactions reduce lock contention
- External calls can timeout and block connections

---

### Rule 8: Handle Concurrency Properly

**Priority**: Medium

**Description**: Implement optimistic concurrency to prevent lost updates when multiple users edit the same record.

**Incorrect**:

```csharp
// No concurrency handling - last write wins
public async Task UpdateProductAsync(int id, UpdateProductRequest request)
{
    var product = await _context.Products.FindAsync(id);
    
    product.Name = request.Name;
    product.Price = request.Price;
    
    await _context.SaveChangesAsync(); // May overwrite another user's changes
}
```

**Correct**:

```csharp
// Entity with concurrency token
public class Product
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public decimal Price { get; set; }
    
    [Timestamp]
    public byte[] RowVersion { get; set; } = null!;
}

// Or with Fluent API
public class ProductConfiguration : IEntityTypeConfiguration<Product>
{
    public void Configure(EntityTypeBuilder<Product> builder)
    {
        builder.Property(p => p.RowVersion)
            .IsRowVersion();
        
        // Or use a regular property for non-SQL Server databases
        builder.Property(p => p.Version)
            .IsConcurrencyToken();
    }
}

// Handle concurrency in service
public async Task<Result> UpdateProductAsync(int id, UpdateProductRequest request)
{
    var product = await _context.Products.FindAsync(id);
    
    if (product is null)
        return Result.NotFound();
    
    // Check if client has stale data
    if (!product.RowVersion.SequenceEqual(request.RowVersion))
        return Result.Conflict("Product was modified by another user");
    
    product.Name = request.Name;
    product.Price = request.Price;
    
    try
    {
        await _context.SaveChangesAsync();
        return Result.Success(product.RowVersion);
    }
    catch (DbUpdateConcurrencyException)
    {
        return Result.Conflict("Product was modified by another user");
    }
}

// Alternative: Reload and retry pattern
public async Task UpdateProductWithRetryAsync(int id, Action<Product> updateAction)
{
    const int maxRetries = 3;
    
    for (int i = 0; i < maxRetries; i++)
    {
        var product = await _context.Products.FindAsync(id);
        if (product is null) throw new NotFoundException();
        
        updateAction(product);
        
        try
        {
            await _context.SaveChangesAsync();
            return;
        }
        catch (DbUpdateConcurrencyException) when (i < maxRetries - 1)
        {
            // Detach and retry
            _context.Entry(product).State = EntityState.Detached;
        }
    }
    
    throw new ConcurrencyException("Failed to update after multiple retries");
}
```

**Why**:
- Prevents silent data loss from concurrent updates
- RowVersion is handled automatically by database
- Client can be notified to refresh and retry
- Critical for multi-user applications

---

## Integration Example

Complete repository pattern with best practices:

```csharp
public interface IProductRepository
{
    Task<PagedResult<ProductDto>> GetPagedAsync(ProductQueryParams query, CancellationToken ct = default);
    Task<ProductDto?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<ProductDto> CreateAsync(CreateProductRequest request, CancellationToken ct = default);
    Task<Result<ProductDto>> UpdateAsync(int id, UpdateProductRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(int id, CancellationToken ct = default);
}

public class ProductRepository : IProductRepository
{
    private readonly AppDbContext _context;
    private readonly IMapper _mapper;

    public ProductRepository(AppDbContext context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public async Task<PagedResult<ProductDto>> GetPagedAsync(
        ProductQueryParams query,
        CancellationToken ct = default)
    {
        var baseQuery = _context.Products.AsNoTracking();

        // Apply filters
        if (!string.IsNullOrWhiteSpace(query.Search))
        {
            baseQuery = baseQuery.Where(p => 
                p.Name.Contains(query.Search) || 
                p.Sku.Contains(query.Search));
        }

        if (query.CategoryId.HasValue)
        {
            baseQuery = baseQuery.Where(p => p.CategoryId == query.CategoryId);
        }

        if (query.MinPrice.HasValue)
        {
            baseQuery = baseQuery.Where(p => p.Price >= query.MinPrice);
        }

        // Get total count
        var totalCount = await baseQuery.CountAsync(ct);

        // Apply sorting and pagination
        var items = await baseQuery
            .OrderBy(p => p.Name)
            .Skip((query.Page - 1) * query.PageSize)
            .Take(query.PageSize)
            .Select(p => new ProductDto
            {
                Id = p.Id,
                Name = p.Name,
                Sku = p.Sku,
                Price = p.Price,
                CategoryName = p.Category.Name,
                StockQuantity = p.Inventory.Quantity
            })
            .ToListAsync(ct);

        return new PagedResult<ProductDto>
        {
            Items = items,
            TotalCount = totalCount,
            Page = query.Page,
            PageSize = query.PageSize
        };
    }

    public async Task<ProductDto?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        return await _context.Products
            .AsNoTracking()
            .Where(p => p.Id == id)
            .Select(p => new ProductDto
            {
                Id = p.Id,
                Name = p.Name,
                Sku = p.Sku,
                Price = p.Price,
                Description = p.Description,
                CategoryName = p.Category.Name,
                RowVersion = p.RowVersion
            })
            .FirstOrDefaultAsync(ct);
    }

    public async Task<ProductDto> CreateAsync(CreateProductRequest request, CancellationToken ct = default)
    {
        var product = _mapper.Map<Product>(request);
        
        _context.Products.Add(product);
        await _context.SaveChangesAsync(ct);

        return _mapper.Map<ProductDto>(product);
    }

    public async Task<Result<ProductDto>> UpdateAsync(
        int id, 
        UpdateProductRequest request,
        CancellationToken ct = default)
    {
        var product = await _context.Products.FindAsync(new object[] { id }, ct);
        
        if (product is null)
            return Result<ProductDto>.NotFound();

        _mapper.Map(request, product);

        try
        {
            await _context.SaveChangesAsync(ct);
            return Result<ProductDto>.Success(_mapper.Map<ProductDto>(product));
        }
        catch (DbUpdateConcurrencyException)
        {
            return Result<ProductDto>.Conflict("Product was modified by another user");
        }
    }

    public async Task<bool> DeleteAsync(int id, CancellationToken ct = default)
    {
        var rowsAffected = await _context.Products
            .Where(p => p.Id == id)
            .ExecuteDeleteAsync(ct);

        return rowsAffected > 0;
    }
}
```

## Checklist

- [ ] No N+1 queries - using Include, projection, or split queries
- [ ] AsNoTracking for read-only operations
- [ ] Projection to DTOs instead of loading full entities
- [ ] Proper pagination at database level
- [ ] Decimal precision configured for money columns
- [ ] Indexes on frequently queried columns
- [ ] Concurrency tokens on frequently updated entities
- [ ] Short transactions without external calls
- [ ] CancellationToken passed to async methods
- [ ] Query logging enabled in development

## References

- [EF Core Performance](https://docs.microsoft.com/ef/core/performance/)
- [EF Core Query Tags](https://docs.microsoft.com/ef/core/querying/tags)
- [Efficient Querying](https://docs.microsoft.com/ef/core/performance/efficient-querying)
- [Change Tracking](https://docs.microsoft.com/ef/core/change-tracking/)

## Changelog

### v1.0.0
- Initial release
- 8 core rules for EF Core optimization
