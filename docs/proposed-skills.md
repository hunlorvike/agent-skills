# Đề Xuất Skills Bổ Sung

Tài liệu này đề xuất các skills bổ sung cho ASP.NET Agent Skills repository, được sắp xếp theo mức độ ưu tiên và giá trị thực tế.

## Skills Đề Xuất (Theo Priority)

### 🔴 Priority: Critical/High

#### 1. **Caching Strategies** (Category: `performance`)
- **Mục đích**: Best practices cho caching trong ASP.NET Core (in-memory, distributed, response caching)
- **Use cases**: 
  - Khi implement caching để tối ưu performance
  - Khi sử dụng Redis hoặc distributed cache
  - Khi cache API responses
- **Priority**: High
- **Rules sẽ cover**:
  - In-memory caching patterns
  - Distributed caching với Redis
  - Response caching middleware
  - Cache invalidation strategies
  - Cache keys và expiration policies

#### 2. **Error Handling Patterns** (Category: `api` hoặc `patterns`)
- **Mục đích**: Global error handling, exception filters, ProblemDetails
- **Use cases**:
  - Khi implement global exception handling
  - Khi design error response format
  - Khi handle unhandled exceptions
- **Priority**: Critical
- **Rules sẽ cover**:
  - Global exception handler middleware
  - Exception filters
  - ProblemDetails format
  - Custom exception types
  - Error logging và correlation

#### 3. **Background Jobs & Tasks** (Category: `patterns` hoặc `infrastructure`)
- **Mục đích**: Hangfire, Quartz.NET, hosted services cho background processing
- **Use cases**:
  - Khi implement background jobs
  - Khi schedule recurring tasks
  - Khi process long-running operations
- **Priority**: High
- **Rules sẽ cover**:
  - Hosted services pattern
  - Hangfire configuration
  - Quartz.NET scheduling
  - Background job best practices
  - Retry và error handling

#### 4. **Message Queues & Event-Driven** (Category: `messaging` hoặc `patterns`)
- **Mục đích**: RabbitMQ, Azure Service Bus, MassTransit patterns
- **Use cases**:
  - Khi implement message queues
  - Khi build event-driven architecture
  - Khi decouple services
- **Priority**: High
- **Rules sẽ cover**:
  - Message queue patterns
  - Event-driven architecture
  - Message serialization
  - Dead letter queues
  - Idempotency

### 🟡 Priority: Medium

#### 5. **Dependency Injection Patterns** (Category: `patterns`)
- **Mục đích**: Advanced DI patterns, service lifetimes, factory patterns
- **Use cases**:
  - Khi design service registration
  - Khi resolve dependencies
  - Khi implement factory patterns
- **Priority**: Medium
- **Rules sẽ cover**:
  - Service lifetimes (Singleton, Scoped, Transient)
  - Factory patterns
  - Options pattern
  - Named services
  - Service locator anti-pattern

#### 6. **Configuration Management** (Category: `configuration`)
- **Mục đích**: IConfiguration, Options pattern, secrets management
- **Use cases**:
  - Khi manage application configuration
  - Khi use Azure Key Vault
  - Khi implement Options pattern
- **Priority**: Medium
- **Rules sẽ cover**:
  - IConfiguration best practices
  - Options pattern
  - Configuration validation
  - Secrets management
  - Environment-specific configs

#### 7. **Middleware Patterns** (Category: `patterns`)
- **Mục đích**: Custom middleware, pipeline ordering, middleware best practices
- **Use cases**:
  - Khi create custom middleware
  - Khi order middleware pipeline
  - Khi implement cross-cutting concerns
- **Priority**: Medium
- **Rules sẽ cover**:
  - Middleware pipeline ordering
  - Custom middleware patterns
  - Request/response modification
  - Middleware performance
  - Conditional middleware

#### 8. **gRPC Services** (Category: `api`)
- **Mục đích**: gRPC service implementation, protobuf, streaming
- **Use cases**:
  - Khi implement gRPC services
  - Khi need high-performance APIs
  - Khi implement microservices communication
- **Priority**: Medium
- **Rules sẽ cover**:
  - gRPC service definition
  - Protobuf best practices
  - Streaming patterns
  - Error handling in gRPC
  - Interceptors

#### 9. **SignalR Real-Time** (Category: `api` hoặc `realtime`)
- **Mục đích**: SignalR hubs, real-time communication, scaling
- **Use cases**:
  - Khi implement real-time features
  - Khi build chat/notifications
  - Khi need WebSocket communication
- **Priority**: Medium
- **Rules sẽ cover**:
  - SignalR hub patterns
  - Connection management
  - Scaling SignalR
  - Authentication/Authorization
  - Error handling

#### 10. **File Upload & Storage** (Category: `storage`)
- **Mục đích**: File uploads, Azure Blob Storage, validation, security
- **Use cases**:
  - Khi implement file uploads
  - Khi store files in cloud
  - Khi handle file processing
- **Priority**: Medium
- **Rules sẽ cover**:
  - Secure file uploads
  - File validation
  - Azure Blob Storage
  - Virus scanning
  - File streaming

### 🟢 Priority: Low/Medium

#### 11. **CQRS & MediatR** (Category: `patterns`)
- **Mục đích**: CQRS pattern với MediatR, command/query separation
- **Use cases**:
  - Khi implement CQRS pattern
  - Khi use MediatR library
  - Khi separate read/write models
- **Priority**: Medium
- **Rules sẽ cover**:
  - CQRS implementation
  - MediatR patterns
  - Command/Query handlers
  - Validation pipelines
  - Event publishing

#### 12. **AutoMapper Best Practices** (Category: `mapping`)
- **Mục đích**: Object mapping, AutoMapper configuration, performance
- **Use cases**:
  - Khi map between DTOs và entities
  - Khi configure AutoMapper
  - Khi optimize mapping performance
- **Priority**: Low
- **Rules sẽ cover**:
  - AutoMapper configuration
  - Profile organization
  - Mapping performance
  - Custom resolvers
  - Projection mapping

#### 13. **Localization & i18n** (Category: `localization`)
- **Mục đích**: Multi-language support, resource files, culture handling
- **Use cases**:
  - Khi support multiple languages
  - Khi implement localization
  - Khi handle culture-specific formatting
- **Priority**: Low
- **Rules sẽ cover**:
  - Resource files
  - Culture providers
  - Localized error messages
  - Date/time formatting
  - Number formatting

#### 14. **API Rate Limiting** (Category: `api` hoặc `security`)
- **Mục đích**: Rate limiting strategies, throttling, quota management
- **Use cases**:
  - Khi implement rate limiting
  - Khi protect APIs from abuse
  - Khi manage API quotas
- **Priority**: Medium
- **Rules sẽ cover**:
  - Rate limiting middleware
  - Different rate limit strategies
  - Per-user vs per-IP
  - Rate limit headers
  - Distributed rate limiting

#### 15. **GraphQL** (Category: `api`)
- **Mục đích**: GraphQL implementation với HotChocolate
- **Use cases**:
  - Khi implement GraphQL APIs
  - Khi need flexible querying
  - Khi build GraphQL schema
- **Priority**: Low
- **Rules sẽ cover**:
  - GraphQL schema design
  - Resolvers
  - DataLoader pattern
  - Authorization
  - Subscriptions

## Categories Mới Đề Xuất

### `performance/` - Performance Optimization
- Caching strategies
- Response compression
- Async/await patterns
- Performance profiling

### `patterns/` - Design Patterns
- CQRS & MediatR
- Dependency Injection patterns
- Middleware patterns
- Factory patterns

### `messaging/` - Messaging & Events
- Message queues
- Event-driven architecture
- Pub/Sub patterns

### `storage/` - File & Storage
- File uploads
- Azure Blob Storage
- File processing

### `configuration/` - Configuration
- Configuration management
- Options pattern
- Secrets management

## Skills Đề Xuất Theo Thứ Tự Ưu Tiên Triển Khai

### Phase 1 (Ngay lập tức - High Value)
1. ✅ **Error Handling Patterns** - Critical, thường dùng
2. ✅ **Caching Strategies** - High impact on performance
3. ✅ **Background Jobs & Tasks** - Common requirement

### Phase 2 (Sớm - Medium Value)
4. ✅ **Dependency Injection Patterns** - Foundation skill
5. ✅ **Configuration Management** - Essential
6. ✅ **Message Queues** - For microservices
7. ✅ **Middleware Patterns** - Cross-cutting concern

### Phase 3 (Sau - Nice to Have)
8. ✅ **gRPC Services** - Specific use case
9. ✅ **SignalR** - Real-time specific
10. ✅ **File Upload & Storage** - Common but specific
11. ✅ **CQRS & MediatR** - Advanced pattern
12. ✅ **API Rate Limiting** - Security/Performance
13. ✅ **AutoMapper** - Utility library
14. ✅ **Localization** - Specific requirement
15. ✅ **GraphQL** - Alternative API style

## Metrics Đề Xuất

Mỗi skill đề xuất nên có:
- **Estimated Rules**: 5-8 rules per skill
- **Complexity**: Low/Medium/High
- **Usage Frequency**: Common/Occasional/Specialized
- **Dependencies**: List required packages

## Next Steps

1. Review và prioritize các skills đề xuất
2. Chọn 3-5 skills để implement đầu tiên
3. Tạo SKILL.md cho các skills được chọn
4. Add scripts và references nếu cần
5. Update README với skills mới

## Feedback

Nếu bạn muốn thêm skills khác hoặc điều chỉnh priority, vui lòng tạo issue hoặc PR.
