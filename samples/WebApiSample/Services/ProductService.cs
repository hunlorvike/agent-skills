using Microsoft.EntityFrameworkCore;
using WebApiSample.Data;
using WebApiSample.Models;

namespace WebApiSample.Services;

public interface IProductService
{
    Task<PagedResponse<ProductDto>> GetPagedAsync(PaginationParams pagination, string? search = null, CancellationToken ct = default);
    Task<ProductDto?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<ProductDto> CreateAsync(CreateProductRequest request, CancellationToken ct = default);
    Task<ProductDto?> UpdateAsync(int id, UpdateProductRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(int id, CancellationToken ct = default);
}

public class ProductService : IProductService
{
    private readonly AppDbContext _context;
    private readonly ILogger<ProductService> _logger;

    public ProductService(AppDbContext context, ILogger<ProductService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<PagedResponse<ProductDto>> GetPagedAsync(
        PaginationParams pagination,
        string? search = null,
        CancellationToken ct = default)
    {
        var query = _context.Products
            .AsNoTracking()
            .Where(p => p.IsActive);

        if (!string.IsNullOrWhiteSpace(search))
        {
            query = query.Where(p =>
                p.Name.Contains(search) ||
                p.Description!.Contains(search) ||
                p.Sku.Contains(search));
        }

        var totalCount = await query.CountAsync(ct);
        var totalPages = (int)Math.Ceiling(totalCount / (double)pagination.PageSize);

        var items = await query
            .OrderBy(p => p.Name)
            .Skip((pagination.PageNumber - 1) * pagination.PageSize)
            .Take(pagination.PageSize)
            .Select(p => new ProductDto(
                p.Id,
                p.Name,
                p.Description,
                p.Price,
                p.Sku,
                p.StockQuantity,
                p.IsActive))
            .ToListAsync(ct);

        _logger.LogInformation(
            "Retrieved {Count} products (page {Page}/{TotalPages})",
            items.Count, pagination.PageNumber, totalPages);

        return new PagedResponse<ProductDto>
        {
            Items = items,
            PageNumber = pagination.PageNumber,
            PageSize = pagination.PageSize,
            TotalCount = totalCount,
            TotalPages = totalPages
        };
    }

    public async Task<ProductDto?> GetByIdAsync(int id, CancellationToken ct = default)
    {
        var product = await _context.Products
            .AsNoTracking()
            .Where(p => p.Id == id && p.IsActive)
            .Select(p => new ProductDto(
                p.Id,
                p.Name,
                p.Description,
                p.Price,
                p.Sku,
                p.StockQuantity,
                p.IsActive))
            .FirstOrDefaultAsync(ct);

        if (product is null)
        {
            _logger.LogWarning("Product {ProductId} not found", id);
        }

        return product;
    }

    public async Task<ProductDto> CreateAsync(CreateProductRequest request, CancellationToken ct = default)
    {
        var product = new Product
        {
            Name = request.Name,
            Description = request.Description,
            Price = request.Price,
            Sku = request.Sku,
            StockQuantity = request.StockQuantity,
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        };

        _context.Products.Add(product);
        await _context.SaveChangesAsync(ct);

        _logger.LogInformation("Created product {ProductId} with SKU {Sku}", product.Id, product.Sku);

        return new ProductDto(
            product.Id,
            product.Name,
            product.Description,
            product.Price,
            product.Sku,
            product.StockQuantity,
            product.IsActive);
    }

    public async Task<ProductDto?> UpdateAsync(int id, UpdateProductRequest request, CancellationToken ct = default)
    {
        var product = await _context.Products.FindAsync(new object[] { id }, ct);

        if (product is null || !product.IsActive)
        {
            _logger.LogWarning("Attempted to update non-existent product {ProductId}", id);
            return null;
        }

        product.Name = request.Name;
        product.Description = request.Description;
        product.Price = request.Price;
        product.StockQuantity = request.StockQuantity;
        product.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync(ct);

        _logger.LogInformation("Updated product {ProductId}", id);

        return new ProductDto(
            product.Id,
            product.Name,
            product.Description,
            product.Price,
            product.Sku,
            product.StockQuantity,
            product.IsActive);
    }

    public async Task<bool> DeleteAsync(int id, CancellationToken ct = default)
    {
        var product = await _context.Products.FindAsync(new object[] { id }, ct);

        if (product is null)
        {
            _logger.LogWarning("Attempted to delete non-existent product {ProductId}", id);
            return false;
        }

        // Soft delete
        product.IsActive = false;
        product.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync(ct);

        _logger.LogInformation("Deleted product {ProductId}", id);
        return true;
    }
}
