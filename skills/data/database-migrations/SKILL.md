---
name: database-migrations
description: Best practices for managing Entity Framework Core migrations including version control, seeding, and deployment strategies.
version: 1.0.0
priority: high
categories:
  - data
  - migrations
  - efcore
use_when:
  - "When managing database schema changes"
  - "When deploying database updates"
  - "When seeding initial data"
  - "When versioning database schema"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.EntityFrameworkCore"
  - "Microsoft.EntityFrameworkCore.Design"
related_skills:
  - efcore-best-practices
---

# Database Migrations Best Practices

## Overview

This skill covers best practices for managing EF Core migrations, including creating, reviewing, and deploying database schema changes safely.

## Rules

### Rule 1: Review Migrations Before Committing

**Priority**: High

**Description**: Always review generated migrations to ensure they're correct and don't contain unwanted changes.

**Incorrect**:

```bash
# Creating migration without review
dotnet ef migrations add AddProductTable
git add .
git commit -m "Add migration"
# Migration might have unwanted changes!
```

**Correct**:

```bash
# Create migration
dotnet ef migrations add AddProductTable

# Review the generated migration file
# Migrations/YYYYMMDDHHMMSS_AddProductTable.cs

# Check what will be applied
dotnet ef migrations script

# Test migration on local database
dotnet ef database update

# Only commit after review
git add Migrations/
git commit -m "Add Product table migration"
```

**Why**:
- Catches unintended schema changes
- Prevents data loss
- Ensures migration correctness
- Better deployment safety

---

### Rule 2: Use Meaningful Migration Names

**Priority**: Medium

**Description**: Use descriptive migration names that explain what changed.

**Incorrect**:

```bash
dotnet ef migrations add Migration1
dotnet ef migrations add Update1
dotnet ef migrations add Fix
```

**Correct**:

```bash
dotnet ef migrations add AddProductTable
dotnet ef migrations add AddOrderStatusColumn
dotnet ef migrations add CreateIndexOnProductSku
dotnet ef migrations add RemoveDeprecatedFields
```

**Why**:
- Clear migration history
- Easier to understand changes
- Better rollback decisions
- Team collaboration

---

### Rule 3: Seed Data Properly

**Priority**: High

**Description**: Use migrations or separate seed methods for initial data.

**Incorrect**:

```csharp
// Seeding in migration - hard to maintain
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.InsertData(
        table: "Products",
        columns: new[] { "Name", "Price" },
        values: new object[] { "Product 1", 10.00m });
    // ... many more inserts
}
```

**Correct**:

```csharp
// Separate seed method
public static class DbSeeder
{
    public static async Task SeedAsync(AppDbContext context)
    {
        if (await context.Products.AnyAsync())
            return; // Already seeded

        var products = new[]
        {
            new Product { Name = "Product 1", Price = 10.00m, Sku = "PROD-001" },
            new Product { Name = "Product 2", Price = 20.00m, Sku = "PROD-002" }
        };

        context.Products.AddRange(products);
        await context.SaveChangesAsync();
    }
}

// Or use IHostApplicationLifetime
var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await DbSeeder.SeedAsync(context);
}

app.Run();
```

**Why**:
- Easier to maintain
- Testable seed logic
- Can be run independently
- Better separation of concerns

---

### Rule 4: Handle Data Migrations Carefully

**Priority**: High

**Description**: Use raw SQL for complex data transformations during migrations.

**Correct**:

```csharp
// Migration with data transformation
public partial class MigrateOrderStatus : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Add new column
        migrationBuilder.AddColumn<string>(
            name: "Status",
            table: "Orders",
            type: "nvarchar(50)",
            nullable: false,
            defaultValue: "Pending");

        // Migrate existing data
        migrationBuilder.Sql(@"
            UPDATE Orders 
            SET Status = CASE 
                WHEN IsProcessed = 1 THEN 'Processed'
                WHEN IsCancelled = 1 THEN 'Cancelled'
                ELSE 'Pending'
            END");

        // Remove old columns after migration
        migrationBuilder.DropColumn(
            name: "IsProcessed",
            table: "Orders");

        migrationBuilder.DropColumn(
            name: "IsCancelled",
            table: "Orders");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Rollback logic
        migrationBuilder.AddColumn<bool>(
            name: "IsProcessed",
            table: "Orders",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<bool>(
            name: "IsCancelled",
            table: "Orders",
            type: "bit",
            nullable: false,
            defaultValue: false);

        migrationBuilder.Sql(@"
            UPDATE Orders 
            SET IsProcessed = CASE WHEN Status = 'Processed' THEN 1 ELSE 0 END,
                IsCancelled = CASE WHEN Status = 'Cancelled' THEN 1 ELSE 0 END");

        migrationBuilder.DropColumn(
            name: "Status",
            table: "Orders");
    }
}
```

**Why**:
- Handles complex data transformations
- Maintains data integrity
- Supports rollback
- Safe migration path

---

## Integration Example

Complete migration workflow:

```bash
# 1. Create migration
dotnet ef migrations add AddProductTable

# 2. Review migration file
# Migrations/YYYYMMDDHHMMSS_AddProductTable.cs

# 3. Generate SQL script
dotnet ef migrations script

# 4. Apply to local database
dotnet ef database update

# 5. Commit to version control
git add Migrations/
git commit -m "Add Product table migration"

# 6. Deploy to production
dotnet ef database update --connection "ProductionConnectionString"
```

## Checklist

- [ ] Migrations reviewed before committing
- [ ] Meaningful migration names
- [ ] Seed data in separate methods
- [ ] Data migrations handled carefully
- [ ] Down migrations implemented
- [ ] Migrations tested locally
- [ ] Migration scripts generated for production

## References

- [EF Core Migrations](https://docs.microsoft.com/ef/core/managing-schemas/migrations/)
- [Applying Migrations](https://docs.microsoft.com/ef/core/managing-schemas/migrations/applying)

## Changelog

### v1.0.0
- Initial release
- 4 core rules for database migrations
