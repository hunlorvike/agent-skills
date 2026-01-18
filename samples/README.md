# Sample Projects

This directory contains sample ASP.NET Core projects that demonstrate the best practices covered by the agent skills.

## Available Samples

### WebApiSample

A complete Web API project demonstrating:

- **API Design**: RESTful endpoints with proper status codes, pagination, and DTOs
- **Authentication**: JWT Bearer token authentication
- **Authorization**: Role-based access control
- **Data Access**: Entity Framework Core with best practices
- **Logging**: Structured logging with Serilog
- **Security**: Rate limiting, security headers, input validation

#### Running the Sample

```bash
cd samples/WebApiSample
dotnet run
```

The API will be available at `https://localhost:5001` with Swagger UI at `/swagger`.

#### Demo Credentials

- Email: `demo@example.com`
- Password: `Demo123!`

#### API Endpoints

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | /api/v1/auth/login | Login and get JWT token | No |
| POST | /api/v1/auth/register | Register new user | No |
| GET | /api/v1/auth/me | Get current user profile | Yes |
| GET | /api/v1/products | List products (paginated) | No |
| GET | /api/v1/products/{id} | Get product by ID | No |
| POST | /api/v1/products | Create product | Admin |
| PUT | /api/v1/products/{id} | Update product | Admin |
| DELETE | /api/v1/products/{id} | Delete product | Admin |
| GET | /health | Health check | No |

## Adding New Samples

When adding a new sample project:

1. Create a new folder under `samples/`
2. Include a README with setup instructions
3. Follow all skills' best practices
4. Add appropriate comments explaining patterns used
