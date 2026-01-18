using System.ComponentModel.DataAnnotations;

namespace WebApiSample.Models;

// Product DTOs
public record ProductDto(
    int Id,
    string Name,
    string? Description,
    decimal Price,
    string Sku,
    int StockQuantity,
    bool IsActive
);

public record CreateProductRequest
{
    [Required]
    [StringLength(200)]
    public required string Name { get; init; }

    [StringLength(2000)]
    public string? Description { get; init; }

    [Required]
    [Range(0.01, 999999.99)]
    public decimal Price { get; init; }

    [Required]
    [StringLength(50)]
    public required string Sku { get; init; }

    [Range(0, int.MaxValue)]
    public int StockQuantity { get; init; }
}

public record UpdateProductRequest
{
    [Required]
    [StringLength(200)]
    public required string Name { get; init; }

    [StringLength(2000)]
    public string? Description { get; init; }

    [Required]
    [Range(0.01, 999999.99)]
    public decimal Price { get; init; }

    [Range(0, int.MaxValue)]
    public int StockQuantity { get; init; }
}

// Auth DTOs
public record LoginRequest
{
    [Required]
    [EmailAddress]
    public required string Email { get; init; }

    [Required]
    public required string Password { get; init; }
}

public record AuthResponse(string AccessToken, DateTime ExpiresAt);

public record RegisterRequest
{
    [Required]
    [StringLength(50)]
    public required string Username { get; init; }

    [Required]
    [EmailAddress]
    public required string Email { get; init; }

    [Required]
    [MinLength(8)]
    public required string Password { get; init; }
}

// Pagination
public record PaginationParams
{
    private const int MaxPageSize = 100;
    private int _pageSize = 10;

    public int PageNumber { get; init; } = 1;

    public int PageSize
    {
        get => _pageSize;
        init => _pageSize = value > MaxPageSize ? MaxPageSize : value;
    }
}

public record PagedResponse<T>
{
    public IReadOnlyList<T> Items { get; init; } = Array.Empty<T>();
    public int PageNumber { get; init; }
    public int PageSize { get; init; }
    public int TotalCount { get; init; }
    public int TotalPages { get; init; }
    public bool HasPreviousPage => PageNumber > 1;
    public bool HasNextPage => PageNumber < TotalPages;
}
