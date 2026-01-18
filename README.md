# ASP.NET Agent Skills

A comprehensive collection of reusable skills for AI agents working with ASP.NET / .NET ecosystem. Inspired by [Vercel's agent-skills](https://github.com/vercel-labs/agent-skills).

## Overview

Agent Skills are modular capability packs that help AI agents understand and apply best practices when working with ASP.NET Core applications. Each skill contains:

- **SKILL.md**: Metadata, guidelines, and code examples
- **scripts/**: Automation scripts for validation (optional)
- **references/**: Supporting documentation (optional)

## Skill Categories

| Category | Description | Skills Count |
|----------|-------------|--------------|
| [API](./skills/api/) | Web API design, routing, versioning | 5 |
| [Auth](./skills/auth/) | Authentication & authorization | 3 |
| [Data](./skills/data/) | Data access & persistence | 3 |
| [Observability](./skills/observability/) | Logging, tracing, health checks | 3 |
| [Testing](./skills/testing/) | Unit & integration testing | 3 |
| [DevOps](./skills/devops/) | CI/CD, containerization | 3 |
| [Security](./skills/security/) | OWASP, headers, validation | 3 |
| [Performance](./skills/performance/) | Caching, optimization | 1 |
| [Patterns](./skills/patterns/) | Design patterns, architecture | 4 |
| [Configuration](./skills/configuration/) | Configuration management | 1 |
| [Messaging](./skills/messaging/) | Message queues, event-driven | 1 |

## Quick Start

### For AI Agents

Skills are designed to be consumed by AI agents. Each `SKILL.md` contains:

```yaml
---
name: skill-name
description: Brief description
use_when:
  - "When reviewing ASP.NET Web API controllers"
  - "When creating new REST endpoints"
priority: critical|high|medium|low
---
```

The `use_when` field helps agents determine when to activate a skill.

### For Developers

1. Browse skills in the [skills/](./skills/) directory
2. Each skill contains practical examples with correct/incorrect code patterns
3. Use the skill-runner tool for automated checks:

```bash
# Install the tool
dotnet tool install --global aspnet-skill-runner

# Run a skill check
skill-runner check webapi-best-practices --path ./src/MyApi
```

## Skill Priority Levels

- **Critical**: Must follow - violations can cause security issues or major bugs
- **High**: Should follow - improves maintainability and performance significantly
- **Medium**: Recommended - follows best practices and conventions
- **Low**: Nice to have - minor improvements and optimizations

## Available Skills

### API & Routing
- `webapi-best-practices` - RESTful design, status codes, DTOs, pagination
- `minimal-api-patterns` - Endpoint routing, validation for Minimal APIs
- `api-versioning` - Header/route versioning strategies
- `openapi-swagger` - OpenAPI spec, Swagger documentation
- `error-handling-patterns` - Global exception handling, ProblemDetails
- `api-rate-limiting` - Rate limiting strategies, quotas, throttling

### Authentication & Authorization
- `jwt-authentication` - JWT Bearer token configuration
- `oauth-oidc-integration` - OAuth 2.0 / OpenID Connect setup
- `policy-based-authorization` - Role/Claim/Policy authorization

### Data & Persistence
- `efcore-best-practices` - N+1 queries, tracking, performance
- `repository-unitofwork` - Repository pattern, UnitOfWork
- `database-migrations` - EF Core migrations, seeding

### Observability & Performance
- `structured-logging` - Serilog/NLog, structured logs, correlation IDs
- `distributed-tracing` - OpenTelemetry, Application Insights
- `health-checks` - Liveness/Readiness probes

### Testing & Quality
- `unit-testing` - xUnit/NUnit, mocking, Arrange-Act-Assert
- `integration-testing` - WebApplicationFactory, TestContainers
- `api-contract-testing` - Contract tests, OpenAPI validation

### DevOps & Deployment
- `docker-containerization` - Dockerfile, multi-stage builds
- `ci-cd-pipelines` - GitHub Actions, Azure DevOps
- `azure-deployment` - App Service, Container Apps, AKS

### Security & Compliance
- `owasp-api-security` - OWASP Top 10 API risks
- `secure-headers` - CORS, CSP, HSTS configuration
- `input-validation` - FluentValidation, model validation

### Performance & Optimization
- `caching-strategies` - In-memory, distributed caching, response caching

### Design Patterns & Architecture
- `background-jobs-tasks` - Hosted services, Hangfire, Quartz.NET
- `dependency-injection-patterns` - Service lifetimes, factory patterns, Options
- `middleware-patterns` - Custom middleware, pipeline ordering
- `cqrs-mediatr` - CQRS pattern, MediatR, command/query handlers

### Configuration Management
- `configuration-management` - IConfiguration, Options pattern, secrets

### Messaging & Event-Driven
- `message-queues-event-driven` - Message queues, event-driven architecture, MassTransit

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on adding new skills.

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Acknowledgments

- Inspired by [Vercel's agent-skills](https://github.com/vercel-labs/agent-skills)
- Built for the .NET community
