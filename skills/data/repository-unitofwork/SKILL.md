---
name: repository-unitofwork
description: Best practices for implementing Repository and UnitOfWork patterns in ASP.NET Core applications for better testability and separation of concerns.
version: 1.0.0
priority: high
categories:
  - data
  - patterns
  - architecture
use_when:
  - "When designing data access layer"
  - "When implementing Clean Architecture"
  - "When improving testability"
  - "When abstracting data access"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.EntityFrameworkCore"
related_skills:
  - efcore-best-practices
  - unit-testing
---

# Repository & UnitOfWork Pattern

## Overview

This skill covers implementing Repository and UnitOfWork patterns in ASP.NET Core. These patterns abstract data access, improve testability, and separate business logic from persistence.

## Rules

### Rule 1: Define Repository Interfaces

**Priority**: High

**Description**: Create interfaces for repositories to enable testing and abstraction.

**Incorrect**:

```csharp
// Direct DbContext usage in services
public class OrderService
{
    private readonly AppDbContext _context;

    public OrderService(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        var order = new Order { /* ... */ };
        _context.Orders.Add(order);
        await _context.SaveChangesAsync(); // Business logic mixed with persistence
        return order;
    }
}
```

**Correct**:

```csharp
// Repository interface
public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IEnumerable<Order>> GetAllAsync(CancellationToken ct = default);
    Task<Order> AddAsync(Order order, CancellationToken ct = default);
    Task UpdateAsync(Order order, CancellationToken ct = default);
    Task DeleteAsync(Order order, CancellationToken ct = default);
    Task<bool> ExistsAsync(int id, CancellationToken ct = default);
}

// Repository implementation
public class OrderRepository : IOrderRepository
{
    private readonly AppDbContext _context;

    public OrderRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Order?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        return await _context.Orders
            .AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == id, ct);
    }

    public async Task<IEnumerable<Order>> GetAllAsync(CancellationToken ct = default)
    {
        return await _context.Orders
            .AsNoTracking()
            .ToListAsync(ct);
    }

    public async Task<Order> AddAsync(Order order, CancellationToken ct = default)
    {
        _context.Orders.Add(order);
        // Don't call SaveChanges here - UnitOfWork handles it
        return order;
    }

    public Task UpdateAsync(Order order, CancellationToken ct = default)
    {
        _context.Orders.Update(order);
        return Task.CompletedTask;
    }

    public Task DeleteAsync(Order order, CancellationToken ct = default)
    {
        _context.Orders.Remove(order);
        return Task.CompletedTask;
    }

    public async Task<bool> ExistsAsync(int id, CancellationToken ct = default)
    {
        return await _context.Orders.AnyAsync(o => o.Id == id, ct);
    }
}

// Service uses repository
public class OrderService
{
    private readonly IOrderRepository _repository;
    private readonly IUnitOfWork _unitOfWork;

    public OrderService(IOrderRepository repository, IUnitOfWork unitOfWork)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
    }

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        var order = new Order { /* ... */ };
        await _repository.AddAsync(order);
        await _unitOfWork.SaveChangesAsync(); // Persistence handled by UnitOfWork
        return order;
    }
}
```

**Why**:
- Enables unit testing with mocks
- Separates business logic from data access
- Makes code more maintainable
- Follows dependency inversion principle

---

### Rule 2: Implement UnitOfWork Pattern

**Priority**: High

**Description**: Use UnitOfWork to manage transactions and coordinate multiple repositories.

**Incorrect**:

```csharp
// Multiple SaveChanges calls
public async Task ProcessOrderAsync(Order order)
{
    _orderRepository.Add(order);
    await _context.SaveChangesAsync();

    _inventoryRepository.Update(order.Items);
    await _context.SaveChangesAsync(); // Separate transaction

    _notificationRepository.Add(new Notification { /* ... */ });
    await _context.SaveChangesAsync(); // Another transaction
    // If this fails, order and inventory are already saved!
}
```

**Correct**:

```csharp
// UnitOfWork interface
public interface IUnitOfWork : IDisposable
{
    IOrderRepository Orders { get; }
    IProductRepository Products { get; }
    IInventoryRepository Inventory { get; }
    
    Task<int> SaveChangesAsync(CancellationToken ct = default);
    Task BeginTransactionAsync(CancellationToken ct = default);
    Task CommitTransactionAsync(CancellationToken ct = default);
    Task RollbackTransactionAsync(CancellationToken ct = default);
}

// UnitOfWork implementation
public class UnitOfWork : IUnitOfWork
{
    private readonly AppDbContext _context;
    private IDbContextTransaction? _transaction;

    public UnitOfWork(AppDbContext context)
    {
        _context = context;
        Orders = new OrderRepository(_context);
        Products = new ProductRepository(_context);
        Inventory = new InventoryRepository(_context);
    }

    public IOrderRepository Orders { get; }
    public IProductRepository Products { get; }
    public IInventoryRepository Inventory { get; }

    public async Task<int> SaveChangesAsync(CancellationToken ct = default)
    {
        return await _context.SaveChangesAsync(ct);
    }

    public async Task BeginTransactionAsync(CancellationToken ct = default)
    {
        _transaction = await _context.Database.BeginTransactionAsync(ct);
    }

    public async Task CommitTransactionAsync(CancellationToken ct = default)
    {
        if (_transaction != null)
        {
            await _transaction.CommitAsync(ct);
            await _transaction.DisposeAsync();
            _transaction = null;
        }
    }

    public async Task RollbackTransactionAsync(CancellationToken ct = default)
    {
        if (_transaction != null)
        {
            await _transaction.RollbackAsync(ct);
            await _transaction.DisposeAsync();
            _transaction = null;
        }
    }

    public void Dispose()
    {
        _transaction?.Dispose();
        _context.Dispose();
    }
}

// Service using UnitOfWork
public class OrderService
{
    private readonly IUnitOfWork _unitOfWork;

    public OrderService(IUnitOfWork unitOfWork)
    {
        _unitOfWork = unitOfWork;
    }

    public async Task ProcessOrderAsync(Order order)
    {
        try
        {
            await _unitOfWork.BeginTransactionAsync();

            // All operations in one transaction
            await _unitOfWork.Orders.AddAsync(order);
            await _unitOfWork.Inventory.UpdateAsync(order.Items);
            await _unitOfWork.Notifications.AddAsync(new Notification { /* ... */ });

            await _unitOfWork.SaveChangesAsync();
            await _unitOfWork.CommitTransactionAsync();
        }
        catch
        {
            await _unitOfWork.RollbackTransactionAsync();
            throw;
        }
    }
}

// Register in DI
builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();
```

**Why**:
- Ensures atomicity across multiple operations
- Single transaction for related changes
- Easier rollback on errors
- Better consistency

---

### Rule 3: Use Generic Repository for Common Operations

**Priority**: Medium

**Description**: Create a generic repository base class for common CRUD operations.

**Correct**:

```csharp
// Generic repository interface
public interface IRepository<T> where T : class
{
    Task<T?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IEnumerable<T>> GetAllAsync(CancellationToken ct = default);
    Task<T> AddAsync(T entity, CancellationToken ct = default);
    Task UpdateAsync(T entity, CancellationToken ct = default);
    Task DeleteAsync(T entity, CancellationToken ct = default);
    Task<bool> ExistsAsync(int id, CancellationToken ct = default);
}

// Generic repository implementation
public class Repository<T> : IRepository<T> where T : class
{
    protected readonly DbContext _context;
    protected readonly DbSet<T> _dbSet;

    public Repository(DbContext context)
    {
        _context = context;
        _dbSet = context.Set<T>();
    }

    public virtual async Task<T?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        return await _dbSet.FindAsync(new object[] { id }, ct);
    }

    public virtual async Task<IEnumerable<T>> GetAllAsync(CancellationToken ct = default)
    {
        return await _dbSet.AsNoTracking().ToListAsync(ct);
    }

    public virtual async Task<T> AddAsync(T entity, CancellationToken ct = default)
    {
        await _dbSet.AddAsync(entity, ct);
        return entity;
    }

    public virtual Task UpdateAsync(T entity, CancellationToken ct = default)
    {
        _dbSet.Update(entity);
        return Task.CompletedTask;
    }

    public virtual Task DeleteAsync(T entity, CancellationToken ct = default)
    {
        _dbSet.Remove(entity);
        return Task.CompletedTask;
    }

    public virtual async Task<bool> ExistsAsync(int id, CancellationToken ct = default)
    {
        // Assumes entity has Id property
        return await _dbSet.AnyAsync(e => EF.Property<int>(e, "Id") == id, ct);
    }
}

// Specific repository extends generic
public interface IOrderRepository : IRepository<Order>
{
    Task<IEnumerable<Order>> GetByCustomerIdAsync(int customerId, CancellationToken ct = default);
    Task<Order?> GetWithItemsAsync(int id, CancellationToken ct = default);
}

public class OrderRepository : Repository<Order>, IOrderRepository
{
    public OrderRepository(AppDbContext context) : base(context)
    {
    }

    public async Task<IEnumerable<Order>> GetByCustomerIdAsync(int customerId, CancellationToken ct = default)
    {
        return await _dbSet
            .AsNoTracking()
            .Where(o => o.CustomerId == customerId)
            .ToListAsync(ct);
    }

    public async Task<Order?> GetWithItemsAsync(int id, CancellationToken ct = default)
    {
        return await _dbSet
            .Include(o => o.Items)
            .AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == id, ct);
    }
}
```

**Why**:
- Reduces code duplication
- Consistent CRUD operations
- Easy to extend with specific methods
- Maintainable base implementation

---

## Integration Example

Complete Repository/UnitOfWork setup:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));

// Register repositories
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<IProductRepository, ProductRepository>();
builder.Services.AddScoped<IUnitOfWork, UnitOfWork>();

// Services
builder.Services.AddScoped<IOrderService, OrderService>();

var app = builder.Build();
app.Run();
```

## Checklist

- [ ] Repository interfaces defined
- [ ] UnitOfWork pattern implemented
- [ ] Generic repository for common operations
- [ ] Repositories registered in DI
- [ ] UnitOfWork manages transactions
- [ ] SaveChanges in UnitOfWork, not repositories
- [ ] Repositories are testable

## References

- [Repository Pattern](https://docs.microsoft.com/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/infrastructure-persistence-layer-design)
- [Unit of Work Pattern](https://martinfowler.com/eaaCatalog/unitOfWork.html)

## Changelog

### v1.0.0
- Initial release
- 3 core rules for Repository/UnitOfWork
