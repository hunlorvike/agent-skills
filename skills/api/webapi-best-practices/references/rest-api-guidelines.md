# REST API Design Guidelines

## HTTP Methods

| Method | Usage | Idempotent | Safe | Request Body | Response Body |
|--------|-------|------------|------|--------------|---------------|
| GET | Retrieve resource(s) | Yes | Yes | No | Yes |
| POST | Create resource | No | No | Yes | Yes |
| PUT | Replace resource | Yes | No | Yes | Optional |
| PATCH | Partial update | No | No | Yes | Yes |
| DELETE | Remove resource | Yes | No | No | No |

## HTTP Status Codes

### Success (2xx)

| Code | Name | When to Use |
|------|------|-------------|
| 200 | OK | Successful GET, PUT, PATCH |
| 201 | Created | Successful POST (include Location header) |
| 202 | Accepted | Request accepted for async processing |
| 204 | No Content | Successful DELETE or PUT with no body |

### Client Errors (4xx)

| Code | Name | When to Use |
|------|------|-------------|
| 400 | Bad Request | Invalid request syntax or validation errors |
| 401 | Unauthorized | Missing or invalid authentication |
| 403 | Forbidden | Valid auth but insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 405 | Method Not Allowed | HTTP method not supported |
| 409 | Conflict | Resource conflict (duplicate, state issue) |
| 422 | Unprocessable Entity | Semantic errors in request |
| 429 | Too Many Requests | Rate limit exceeded |

### Server Errors (5xx)

| Code | Name | When to Use |
|------|------|-------------|
| 500 | Internal Server Error | Unhandled server exception |
| 502 | Bad Gateway | Upstream service error |
| 503 | Service Unavailable | Service temporarily unavailable |
| 504 | Gateway Timeout | Upstream service timeout |

## URL Design

### Good Practices

```
GET    /api/v1/orders              # List orders
GET    /api/v1/orders/123          # Get order 123
POST   /api/v1/orders              # Create order
PUT    /api/v1/orders/123          # Replace order 123
PATCH  /api/v1/orders/123          # Update order 123
DELETE /api/v1/orders/123          # Delete order 123

GET    /api/v1/orders/123/items    # Get items for order 123
POST   /api/v1/orders/123/items    # Add item to order 123

POST   /api/v1/orders/123/cancel   # Action: cancel order
POST   /api/v1/orders/123/ship     # Action: ship order
```

### Anti-Patterns (Avoid)

```
GET    /api/v1/getOrders           # Verb in URL
POST   /api/v1/createOrder         # Redundant verb
GET    /api/v1/order/delete/123    # Wrong method
POST   /api/v1/orders/123          # POST for update
```

## Pagination

### Request Parameters

```
GET /api/v1/products?page=2&pageSize=20&sort=name&order=asc
```

### Response Format

```json
{
  "items": [...],
  "pageNumber": 2,
  "pageSize": 20,
  "totalCount": 150,
  "totalPages": 8,
  "hasPreviousPage": true,
  "hasNextPage": true
}
```

## Filtering & Searching

```
GET /api/v1/products?category=electronics&minPrice=100&maxPrice=500
GET /api/v1/products?search=laptop
GET /api/v1/products?status=active,pending
```

## Error Response Format (ProblemDetails)

```json
{
  "type": "https://tools.ietf.org/html/rfc7231#section-6.5.1",
  "title": "Validation failed",
  "status": 400,
  "detail": "One or more validation errors occurred.",
  "instance": "/api/v1/orders",
  "traceId": "00-abc123-def456-00",
  "errors": {
    "CustomerEmail": ["Invalid email format"],
    "Items": ["At least one item is required"]
  }
}
```

## Versioning Strategies

### URL Path (Recommended)
```
/api/v1/orders
/api/v2/orders
```

### Query String
```
/api/orders?version=1.0
```

### Header
```
Accept: application/json; version=1.0
Api-Version: 1.0
```

## HATEOAS Links (Optional)

```json
{
  "id": 123,
  "status": "pending",
  "_links": {
    "self": { "href": "/api/v1/orders/123" },
    "cancel": { "href": "/api/v1/orders/123/cancel", "method": "POST" },
    "items": { "href": "/api/v1/orders/123/items" }
  }
}
```

## References

- [Microsoft REST API Guidelines](https://github.com/microsoft/api-guidelines)
- [JSON:API Specification](https://jsonapi.org/)
- [RFC 7807 - Problem Details](https://datatracker.ietf.org/doc/html/rfc7807)
