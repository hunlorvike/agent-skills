using Microsoft.EntityFrameworkCore;
using WebApiSample.Models;

namespace WebApiSample.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<Product> Products => Set<Product>();
    public DbSet<User> Users => Set<User>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Product configuration
        modelBuilder.Entity<Product>(entity =>
        {
            entity.HasKey(e => e.Id);
            
            entity.Property(e => e.Name)
                .IsRequired()
                .HasMaxLength(200);
            
            entity.Property(e => e.Sku)
                .IsRequired()
                .HasMaxLength(50);
            
            entity.Property(e => e.Description)
                .HasMaxLength(2000);
            
            entity.Property(e => e.Price)
                .HasPrecision(18, 2);
            
            entity.Property(e => e.RowVersion)
                .IsRowVersion();
            
            entity.HasIndex(e => e.Sku)
                .IsUnique();
            
            entity.HasIndex(e => e.Name);
        });

        // User configuration
        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.Id);
            
            entity.Property(e => e.Username)
                .IsRequired()
                .HasMaxLength(50);
            
            entity.Property(e => e.Email)
                .IsRequired()
                .HasMaxLength(256);
            
            entity.Property(e => e.PasswordHash)
                .IsRequired();
            
            entity.HasIndex(e => e.Email)
                .IsUnique();
            
            entity.HasIndex(e => e.Username)
                .IsUnique();
        });
    }
}

public static class DbSeeder
{
    public static async Task SeedAsync(AppDbContext context)
    {
        if (await context.Products.AnyAsync())
            return;

        var products = new List<Product>
        {
            new() { Name = "Laptop Pro", Description = "High-performance laptop", Price = 1299.99m, Sku = "LAP-001", StockQuantity = 50, CreatedAt = DateTime.UtcNow },
            new() { Name = "Wireless Mouse", Description = "Ergonomic wireless mouse", Price = 49.99m, Sku = "MOU-001", StockQuantity = 200, CreatedAt = DateTime.UtcNow },
            new() { Name = "USB-C Hub", Description = "7-in-1 USB-C hub", Price = 79.99m, Sku = "HUB-001", StockQuantity = 100, CreatedAt = DateTime.UtcNow },
            new() { Name = "Mechanical Keyboard", Description = "RGB mechanical keyboard", Price = 149.99m, Sku = "KEY-001", StockQuantity = 75, CreatedAt = DateTime.UtcNow },
            new() { Name = "Monitor 27\"", Description = "4K IPS monitor", Price = 399.99m, Sku = "MON-001", StockQuantity = 30, CreatedAt = DateTime.UtcNow },
        };

        context.Products.AddRange(products);

        // Add demo user (password: Demo123!)
        var demoUser = new User
        {
            Username = "demo",
            Email = "demo@example.com",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("Demo123!"),
            Role = "Admin",
            CreatedAt = DateTime.UtcNow
        };
        context.Users.Add(demoUser);

        await context.SaveChangesAsync();
    }
}
