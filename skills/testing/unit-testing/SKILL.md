---
name: unit-testing
description: Best practices for writing effective unit tests in ASP.NET Core applications using xUnit, NUnit, or MSTest with proper mocking, naming conventions, and test organization.
version: 1.0.0
priority: critical
categories:
  - testing
  - quality
  - tdd
use_when:
  - "When writing unit tests for services or controllers"
  - "When reviewing test code"
  - "When setting up test infrastructure"
  - "When improving test coverage"
  - "When refactoring existing tests"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "xUnit, NUnit, or MSTest"
  - "Moq or NSubstitute"
related_skills:
  - integration-testing
  - api-contract-testing
  - webapi-best-practices
---

# Unit Testing Best Practices

## Overview

This skill covers best practices for writing maintainable, reliable unit tests in ASP.NET Core. Good unit tests:

- Are fast and isolated
- Follow consistent patterns
- Have clear assertions
- Are easy to maintain
- Provide meaningful failure messages

## Rules

### Rule 1: Follow the Arrange-Act-Assert Pattern

**Priority**: Critical

**Description**: Structure all tests using the AAA pattern for clarity and consistency.

**Incorrect**:

```csharp
[Fact]
public async Task ProcessOrder_Test()
{
    var service = new OrderService(_mockRepo.Object, _mockLogger.Object);
    _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync(new Order { Id = 1, Status = OrderStatus.Pending });
    var result = await service.ProcessOrderAsync(1);
    Assert.NotNull(result);
    _mockRepo.Setup(r => r.UpdateAsync(It.IsAny<Order>())).Returns(Task.CompletedTask);
    Assert.Equal(OrderStatus.Processed, result.Status);
}
```

**Correct**:

```csharp
[Fact]
public async Task ProcessOrderAsync_WithPendingOrder_ShouldSetStatusToProcessed()
{
    // Arrange
    var order = new Order { Id = 1, Status = OrderStatus.Pending };
    _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync(order);
    _mockRepo.Setup(r => r.UpdateAsync(It.IsAny<Order>())).Returns(Task.CompletedTask);
    
    var service = new OrderService(_mockRepo.Object, _mockLogger.Object);

    // Act
    var result = await service.ProcessOrderAsync(1);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(OrderStatus.Processed, result.Status);
    _mockRepo.Verify(r => r.UpdateAsync(It.Is<Order>(o => o.Status == OrderStatus.Processed)), Times.Once);
}
```

**Why**:
- Clear visual separation of test phases
- Easier to identify test setup, execution, and verification
- Makes tests self-documenting
- Helps identify tests that are doing too much

---

### Rule 2: Use Descriptive Test Names

**Priority**: High

**Description**: Test names should clearly describe what is being tested, under what conditions, and what the expected outcome is.

**Incorrect**:

```csharp
[Fact]
public void Test1() { }

[Fact]
public void OrderServiceTest() { }

[Fact]
public void ProcessOrder() { }

[Fact]
public void ShouldWork() { }

[Fact]
public async Task TestProcessOrderWithValidData() { }
```

**Correct**:

```csharp
// Pattern: MethodName_Condition_ExpectedResult
[Fact]
public async Task ProcessOrderAsync_WithValidOrder_ReturnsProcessedOrder()

[Fact]
public async Task ProcessOrderAsync_WithNullOrder_ThrowsArgumentNullException()

[Fact]
public async Task ProcessOrderAsync_WhenOrderAlreadyProcessed_ThrowsInvalidOperationException()

// Pattern: Should_ExpectedBehavior_When_Condition
[Fact]
public async Task Should_ReturnNotFound_When_OrderDoesNotExist()

[Fact]
public void Should_CalculateCorrectTotal_When_OrderHasMultipleItems()

// For theory/parameterized tests
[Theory]
[InlineData(0)]
[InlineData(-1)]
[InlineData(-100)]
public void ValidateQuantity_WithInvalidQuantity_ReturnsFalse(int quantity)
```

**Why**:
- Tests serve as documentation
- Failed test names immediately indicate what broke
- Makes test discovery easier
- Helps identify missing test cases

---

### Rule 3: Test One Thing Per Test

**Priority**: High

**Description**: Each test should verify one specific behavior. Multiple assertions are fine if they verify the same logical outcome.

**Incorrect**:

```csharp
[Fact]
public async Task OrderService_AllOperations_Work()
{
    var service = new OrderService(_mockRepo.Object);
    
    // Testing create
    var created = await service.CreateOrderAsync(new CreateOrderRequest());
    Assert.NotNull(created);
    
    // Testing get
    var retrieved = await service.GetOrderAsync(created.Id);
    Assert.Equal(created.Id, retrieved.Id);
    
    // Testing update
    await service.UpdateOrderAsync(created.Id, new UpdateOrderRequest());
    
    // Testing delete
    await service.DeleteOrderAsync(created.Id);
    var deleted = await service.GetOrderAsync(created.Id);
    Assert.Null(deleted);
}
```

**Correct**:

```csharp
[Fact]
public async Task CreateOrderAsync_WithValidRequest_ReturnsNewOrder()
{
    // Arrange
    var request = new CreateOrderRequest { CustomerId = 1, Items = new List<OrderItem>() };
    _mockRepo.Setup(r => r.AddAsync(It.IsAny<Order>()))
        .ReturnsAsync((Order o) => { o.Id = 1; return o; });
    
    var service = new OrderService(_mockRepo.Object);

    // Act
    var result = await service.CreateOrderAsync(request);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(1, result.Id);
    Assert.Equal(1, result.CustomerId);
}

[Fact]
public async Task GetOrderAsync_WithExistingId_ReturnsOrder()
{
    // Arrange
    var expectedOrder = new Order { Id = 1, CustomerId = 1 };
    _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync(expectedOrder);
    
    var service = new OrderService(_mockRepo.Object);

    // Act
    var result = await service.GetOrderAsync(1);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(expectedOrder.Id, result.Id);
}

[Fact]
public async Task GetOrderAsync_WithNonExistingId_ReturnsNull()
{
    // Arrange
    _mockRepo.Setup(r => r.GetByIdAsync(999)).ReturnsAsync((Order?)null);
    
    var service = new OrderService(_mockRepo.Object);

    // Act
    var result = await service.GetOrderAsync(999);

    // Assert
    Assert.Null(result);
}
```

**Why**:
- Easier to identify what failed
- Tests are more focused and readable
- Simpler to maintain
- Better test coverage visibility

---

### Rule 4: Use Proper Mocking Practices

**Priority**: High

**Description**: Mock only external dependencies, not the system under test. Use strict mocks when appropriate and verify interactions.

**Incorrect**:

```csharp
[Fact]
public async Task ProcessOrder_Test()
{
    // Mocking the system under test - wrong!
    var mockService = new Mock<IOrderService>();
    mockService.Setup(s => s.ProcessOrderAsync(1))
        .ReturnsAsync(new Order { Status = OrderStatus.Processed });
    
    var result = await mockService.Object.ProcessOrderAsync(1);
    Assert.Equal(OrderStatus.Processed, result.Status);
}

[Fact]
public async Task ProcessOrder_LooseMock_HidesProblems()
{
    // Loose mock returns default values for unconfigured methods
    var mockRepo = new Mock<IOrderRepository>();
    // No setup - GetByIdAsync returns null but test might still pass
    
    var service = new OrderService(mockRepo.Object);
    // This might not behave as expected
}
```

**Correct**:

```csharp
public class OrderServiceTests
{
    private readonly Mock<IOrderRepository> _mockRepo;
    private readonly Mock<ILogger<OrderService>> _mockLogger;
    private readonly OrderService _sut; // System Under Test

    public OrderServiceTests()
    {
        _mockRepo = new Mock<IOrderRepository>(MockBehavior.Strict);
        _mockLogger = new Mock<ILogger<OrderService>>();
        _sut = new OrderService(_mockRepo.Object, _mockLogger.Object);
    }

    [Fact]
    public async Task ProcessOrderAsync_WithPendingOrder_UpdatesAndReturnsOrder()
    {
        // Arrange
        var order = new Order { Id = 1, Status = OrderStatus.Pending };
        
        _mockRepo.Setup(r => r.GetByIdAsync(1))
            .ReturnsAsync(order)
            .Verifiable();
        
        _mockRepo.Setup(r => r.UpdateAsync(It.Is<Order>(o => 
            o.Id == 1 && o.Status == OrderStatus.Processed)))
            .Returns(Task.CompletedTask)
            .Verifiable();

        // Act
        var result = await _sut.ProcessOrderAsync(1);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(OrderStatus.Processed, result.Status);
        
        _mockRepo.Verify(); // Verify all marked as Verifiable were called
        _mockRepo.VerifyNoOtherCalls(); // Ensure no unexpected calls
    }

    [Fact]
    public async Task ProcessOrderAsync_WithNonExistingOrder_ThrowsNotFoundException()
    {
        // Arrange
        _mockRepo.Setup(r => r.GetByIdAsync(999))
            .ReturnsAsync((Order?)null);

        // Act & Assert
        await Assert.ThrowsAsync<NotFoundException>(
            () => _sut.ProcessOrderAsync(999));
    }
}

// Using NSubstitute alternative
public class OrderServiceNSubstituteTests
{
    private readonly IOrderRepository _repo;
    private readonly OrderService _sut;

    public OrderServiceNSubstituteTests()
    {
        _repo = Substitute.For<IOrderRepository>();
        _sut = new OrderService(_repo, Substitute.For<ILogger<OrderService>>());
    }

    [Fact]
    public async Task ProcessOrderAsync_CallsUpdateWithProcessedStatus()
    {
        // Arrange
        var order = new Order { Id = 1, Status = OrderStatus.Pending };
        _repo.GetByIdAsync(1).Returns(order);

        // Act
        await _sut.ProcessOrderAsync(1);

        // Assert
        await _repo.Received(1).UpdateAsync(
            Arg.Is<Order>(o => o.Status == OrderStatus.Processed));
    }
}
```

**Why**:
- Mocking the SUT tests the mock, not the code
- Strict mocks catch unexpected behavior
- Verification ensures correct interactions
- Clear separation between dependencies and SUT

---

### Rule 5: Use Theory Tests for Multiple Test Cases

**Priority**: Medium

**Description**: Use parameterized tests (Theory) instead of duplicating test methods for different inputs.

**Incorrect**:

```csharp
[Fact]
public void ValidateEmail_WithValidEmail1_ReturnsTrue()
{
    var result = EmailValidator.IsValid("test@example.com");
    Assert.True(result);
}

[Fact]
public void ValidateEmail_WithValidEmail2_ReturnsTrue()
{
    var result = EmailValidator.IsValid("user.name@domain.org");
    Assert.True(result);
}

[Fact]
public void ValidateEmail_WithInvalidEmail1_ReturnsFalse()
{
    var result = EmailValidator.IsValid("invalid");
    Assert.False(result);
}

[Fact]
public void ValidateEmail_WithInvalidEmail2_ReturnsFalse()
{
    var result = EmailValidator.IsValid("@domain.com");
    Assert.False(result);
}
// ... many more duplicated tests
```

**Correct**:

```csharp
[Theory]
[InlineData("test@example.com", true)]
[InlineData("user.name@domain.org", true)]
[InlineData("user+tag@example.com", true)]
[InlineData("invalid", false)]
[InlineData("@domain.com", false)]
[InlineData("user@", false)]
[InlineData("", false)]
[InlineData(null, false)]
public void IsValid_WithVariousInputs_ReturnsExpectedResult(string? email, bool expected)
{
    // Act
    var result = EmailValidator.IsValid(email);

    // Assert
    Assert.Equal(expected, result);
}

// For complex test data, use MemberData
public static IEnumerable<object[]> OrderCalculationData => new List<object[]>
{
    new object[] { new[] { 10.0m, 20.0m }, 0m, 30.0m },      // No discount
    new object[] { new[] { 100.0m }, 10m, 90.0m },           // 10% discount
    new object[] { new[] { 50.0m, 50.0m }, 25m, 75.0m },     // 25% discount
};

[Theory]
[MemberData(nameof(OrderCalculationData))]
public void CalculateTotal_WithItemsAndDiscount_ReturnsCorrectTotal(
    decimal[] itemPrices, 
    decimal discountPercent, 
    decimal expectedTotal)
{
    // Arrange
    var order = new Order
    {
        Items = itemPrices.Select(p => new OrderItem { Price = p }).ToList(),
        DiscountPercent = discountPercent
    };

    // Act
    var result = order.CalculateTotal();

    // Assert
    Assert.Equal(expectedTotal, result);
}

// Using ClassData for complex scenarios
public class InvalidOrderDataGenerator : IEnumerable<object[]>
{
    public IEnumerator<object[]> GetEnumerator()
    {
        yield return new object[] { null, "Order cannot be null" };
        yield return new object[] { new Order { Items = null }, "Items cannot be null" };
        yield return new object[] { new Order { Items = new List<OrderItem>() }, "Order must have items" };
    }

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}

[Theory]
[ClassData(typeof(InvalidOrderDataGenerator))]
public void ValidateOrder_WithInvalidOrder_ReturnsExpectedError(Order? order, string expectedError)
{
    // Act
    var result = OrderValidator.Validate(order);

    // Assert
    Assert.False(result.IsValid);
    Assert.Contains(expectedError, result.Errors);
}
```

**Why**:
- Reduces code duplication
- Easy to add new test cases
- Clear visibility of all tested scenarios
- Same test logic, different data

---

### Rule 6: Handle Async Tests Properly

**Priority**: High

**Description**: Use async/await correctly in tests. Don't mix synchronous and asynchronous patterns.

**Incorrect**:

```csharp
// Blocking on async - can cause deadlocks
[Fact]
public void GetOrder_ReturnsOrder()
{
    var result = _service.GetOrderAsync(1).Result; // Bad!
    Assert.NotNull(result);
}

// Missing await
[Fact]
public async Task ProcessOrder_Processes()
{
    _service.ProcessOrderAsync(1); // Missing await - test passes regardless
}

// Using async void - exceptions are lost
[Fact]
public async void ProcessOrder_Test() // async void is wrong!
{
    await _service.ProcessOrderAsync(1);
}
```

**Correct**:

```csharp
// Proper async test
[Fact]
public async Task GetOrderAsync_WithValidId_ReturnsOrder()
{
    // Arrange
    var expectedOrder = new Order { Id = 1 };
    _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync(expectedOrder);

    // Act
    var result = await _sut.GetOrderAsync(1);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(1, result.Id);
}

// Testing for exceptions
[Fact]
public async Task GetOrderAsync_WithInvalidId_ThrowsNotFoundException()
{
    // Arrange
    _mockRepo.Setup(r => r.GetByIdAsync(-1)).ReturnsAsync((Order?)null);

    // Act & Assert
    var exception = await Assert.ThrowsAsync<NotFoundException>(
        () => _sut.GetOrderAsync(-1));
    
    Assert.Contains("-1", exception.Message);
}

// Testing cancellation
[Fact]
public async Task LongRunningOperation_WhenCancelled_ThrowsOperationCancelledException()
{
    // Arrange
    using var cts = new CancellationTokenSource();
    cts.Cancel();

    // Act & Assert
    await Assert.ThrowsAsync<OperationCanceledException>(
        () => _sut.LongRunningOperationAsync(cts.Token));
}

// Testing multiple async operations
[Fact]
public async Task BatchProcess_ProcessesAllItems()
{
    // Arrange
    var items = new[] { 1, 2, 3 };
    foreach (var id in items)
    {
        _mockRepo.Setup(r => r.ProcessAsync(id)).Returns(Task.CompletedTask);
    }

    // Act
    await _sut.BatchProcessAsync(items);

    // Assert
    foreach (var id in items)
    {
        _mockRepo.Verify(r => r.ProcessAsync(id), Times.Once);
    }
}
```

**Why**:
- Blocking can cause deadlocks in certain contexts
- Missing await means test passes even if operation fails
- async void loses exception information
- Proper async testing catches timing issues

---

### Rule 7: Use Test Fixtures for Shared Setup

**Priority**: Medium

**Description**: Use fixtures for expensive setup that can be shared across tests without causing side effects.

**Incorrect**:

```csharp
// Creating expensive resources in each test
public class DatabaseTests
{
    [Fact]
    public async Task Test1()
    {
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync();
        // ... test
    }

    [Fact]
    public async Task Test2()
    {
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync();
        // ... same setup repeated
    }
}
```

**Correct**:

```csharp
// Class fixture - shared across all tests in the class
public class DatabaseFixture : IAsyncLifetime
{
    public SqlConnection Connection { get; private set; } = null!;
    
    public async Task InitializeAsync()
    {
        Connection = new SqlConnection(TestConfiguration.ConnectionString);
        await Connection.OpenAsync();
        await SeedTestDataAsync();
    }

    public async Task DisposeAsync()
    {
        await CleanupTestDataAsync();
        await Connection.DisposeAsync();
    }

    private async Task SeedTestDataAsync() { /* ... */ }
    private async Task CleanupTestDataAsync() { /* ... */ }
}

public class DatabaseTests : IClassFixture<DatabaseFixture>
{
    private readonly DatabaseFixture _fixture;

    public DatabaseTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task Test1()
    {
        // Use _fixture.Connection - already open
    }

    [Fact]
    public async Task Test2()
    {
        // Same connection reused
    }
}

// Collection fixture - shared across multiple test classes
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture>
{
}

[Collection("Database")]
public class OrderRepositoryTests
{
    private readonly DatabaseFixture _fixture;

    public OrderRepositoryTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }
}

[Collection("Database")]
public class CustomerRepositoryTests
{
    private readonly DatabaseFixture _fixture;

    public CustomerRepositoryTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
    }
}
```

**Why**:
- Reduces test execution time
- Expensive operations (DB connections, containers) done once
- Consistent test data across tests
- Proper cleanup via IAsyncLifetime

---

## Integration Example

Complete test class following all best practices:

```csharp
using Moq;
using Xunit;

namespace MyApp.Tests.Services;

public class OrderServiceTests
{
    private readonly Mock<IOrderRepository> _mockRepo;
    private readonly Mock<IPaymentService> _mockPayment;
    private readonly Mock<ILogger<OrderService>> _mockLogger;
    private readonly OrderService _sut;

    public OrderServiceTests()
    {
        _mockRepo = new Mock<IOrderRepository>();
        _mockPayment = new Mock<IPaymentService>();
        _mockLogger = new Mock<ILogger<OrderService>>();
        
        _sut = new OrderService(
            _mockRepo.Object,
            _mockPayment.Object,
            _mockLogger.Object);
    }

    #region CreateOrderAsync Tests

    [Fact]
    public async Task CreateOrderAsync_WithValidRequest_ReturnsCreatedOrder()
    {
        // Arrange
        var request = CreateValidOrderRequest();
        var expectedOrder = new Order { Id = 1, CustomerId = request.CustomerId };
        
        _mockRepo.Setup(r => r.AddAsync(It.IsAny<Order>()))
            .ReturnsAsync(expectedOrder);

        // Act
        var result = await _sut.CreateOrderAsync(request);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(expectedOrder.Id, result.Id);
        Assert.Equal(OrderStatus.Pending, result.Status);
    }

    [Fact]
    public async Task CreateOrderAsync_WithNullRequest_ThrowsArgumentNullException()
    {
        // Act & Assert
        await Assert.ThrowsAsync<ArgumentNullException>(
            () => _sut.CreateOrderAsync(null!));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public async Task CreateOrderAsync_WithInvalidCustomerId_ThrowsValidationException(int customerId)
    {
        // Arrange
        var request = new CreateOrderRequest { CustomerId = customerId };

        // Act & Assert
        var exception = await Assert.ThrowsAsync<ValidationException>(
            () => _sut.CreateOrderAsync(request));
        
        Assert.Contains("CustomerId", exception.Message);
    }

    #endregion

    #region ProcessOrderAsync Tests

    [Fact]
    public async Task ProcessOrderAsync_WithPendingOrder_ProcessesSuccessfully()
    {
        // Arrange
        var order = new Order { Id = 1, Status = OrderStatus.Pending, TotalAmount = 100 };
        
        _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync(order);
        _mockPayment.Setup(p => p.ChargeAsync(order.Id, order.TotalAmount))
            .ReturnsAsync(true);
        _mockRepo.Setup(r => r.UpdateAsync(It.IsAny<Order>()))
            .Returns(Task.CompletedTask);

        // Act
        var result = await _sut.ProcessOrderAsync(1);

        // Assert
        Assert.Equal(OrderStatus.Processed, result.Status);
        _mockPayment.Verify(p => p.ChargeAsync(1, 100), Times.Once);
        _mockRepo.Verify(r => r.UpdateAsync(It.Is<Order>(o => 
            o.Status == OrderStatus.Processed)), Times.Once);
    }

    [Fact]
    public async Task ProcessOrderAsync_WhenPaymentFails_SetsStatusToFailed()
    {
        // Arrange
        var order = new Order { Id = 1, Status = OrderStatus.Pending, TotalAmount = 100 };
        
        _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync(order);
        _mockPayment.Setup(p => p.ChargeAsync(It.IsAny<int>(), It.IsAny<decimal>()))
            .ReturnsAsync(false);
        _mockRepo.Setup(r => r.UpdateAsync(It.IsAny<Order>()))
            .Returns(Task.CompletedTask);

        // Act
        var result = await _sut.ProcessOrderAsync(1);

        // Assert
        Assert.Equal(OrderStatus.PaymentFailed, result.Status);
    }

    [Fact]
    public async Task ProcessOrderAsync_WithNonExistingOrder_ThrowsNotFoundException()
    {
        // Arrange
        _mockRepo.Setup(r => r.GetByIdAsync(999)).ReturnsAsync((Order?)null);

        // Act & Assert
        await Assert.ThrowsAsync<NotFoundException>(
            () => _sut.ProcessOrderAsync(999));
    }

    #endregion

    #region Helper Methods

    private static CreateOrderRequest CreateValidOrderRequest() => new()
    {
        CustomerId = 1,
        Items = new List<OrderItemRequest>
        {
            new() { ProductId = 1, Quantity = 2 },
            new() { ProductId = 2, Quantity = 1 }
        }
    };

    #endregion
}
```

## Checklist

- [ ] Tests follow Arrange-Act-Assert pattern
- [ ] Test names describe what, condition, and expected result
- [ ] Each test verifies one logical behavior
- [ ] Mocks are for dependencies, not the SUT
- [ ] Theory tests used for parameterized scenarios
- [ ] Async tests use async/await properly (not .Result)
- [ ] Fixtures used for expensive shared setup
- [ ] Tests are independent and can run in any order
- [ ] No test relies on another test's side effects
- [ ] Assertions have meaningful failure messages

## References

- [Unit Testing Best Practices](https://docs.microsoft.com/dotnet/core/testing/unit-testing-best-practices)
- [xUnit Documentation](https://xunit.net/)
- [Moq Quickstart](https://github.com/moq/moq4/wiki/Quickstart)
- [NSubstitute Documentation](https://nsubstitute.github.io/)

## Changelog

### v1.0.0
- Initial release
- 7 core rules for unit testing
