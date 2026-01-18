---
name: docker-containerization
description: Best practices for containerizing ASP.NET Core applications using Docker including multi-stage builds, optimization, and security considerations.
version: 1.0.0
priority: high
categories:
  - devops
  - docker
  - containers
use_when:
  - "When containerizing ASP.NET applications"
  - "When deploying to container platforms"
  - "When optimizing Docker images"
  - "When preparing for Kubernetes"
prerequisites:
  - "Docker Desktop or Docker Engine"
  - "ASP.NET Core 8.0+"
related_skills:
  - ci-cd-pipelines
  - azure-deployment
---

# Docker Containerization Best Practices

## Overview

This skill covers best practices for creating optimized, secure Docker images for ASP.NET Core applications.

## Rules

### Rule 1: Use Multi-Stage Builds

**Priority**: High

**Description**: Use multi-stage builds to create smaller, more secure production images.

**Incorrect**:

```dockerfile
# Single stage - includes build tools in production
FROM mcr.microsoft.com/dotnet/sdk:8.0
WORKDIR /app
COPY . .
RUN dotnet publish -c Release -o out
ENTRYPOINT ["dotnet", "out/MyApp.dll"]
# Image is large and includes unnecessary tools
```

**Correct**:

```dockerfile
# Multi-stage build
# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["MyApp.csproj", "./"]
RUN dotnet restore "MyApp.csproj"

# Copy everything else and build
COPY . .
WORKDIR "/src"
RUN dotnet build "MyApp.csproj" -c Release -o /app/build

# Stage 2: Publish
FROM build AS publish
RUN dotnet publish "MyApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Stage 3: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy published app
COPY --from=publish /app/publish .

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

ENTRYPOINT ["dotnet", "MyApp.dll"]
```

**Why**:
- Smaller production images
- No build tools in production
- Better security
- Faster deployments

---

### Rule 2: Optimize Layer Caching

**Priority**: High

**Description**: Order Dockerfile commands to maximize cache hits.

**Incorrect**:

```dockerfile
# Bad order - changes to code invalidate dependency cache
FROM mcr.microsoft.com/dotnet/sdk:8.0
WORKDIR /app
COPY . .
RUN dotnet restore
RUN dotnet build
RUN dotnet publish
```

**Correct**:

```dockerfile
# Good order - dependencies cached separately
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy only project files first
COPY ["MyApp.csproj", "Directory.Build.props", "./"]
# Restore dependencies (cached if csproj unchanged)
RUN dotnet restore "MyApp.csproj"

# Copy source code (only invalidates if code changes)
COPY . .
# Build and publish
RUN dotnet build "MyApp.csproj" -c Release -o /app/build
RUN dotnet publish "MyApp.csproj" -c Release -o /app/publish
```

**Why**:
- Faster builds
- Better cache utilization
- Reduced build times
- Lower CI/CD costs

---

### Rule 3: Use .dockerignore

**Priority**: Medium

**Description**: Exclude unnecessary files from Docker build context.

**Incorrect**:

```dockerfile
# No .dockerignore - copies everything
COPY . .
# Includes bin/, obj/, .git/, etc.
```

**Correct**:

```dockerignore
# .dockerignore
**/.dockerignore
**/.git
**/.gitignore
**/.vs
**/.vscode
**/.idea
**/*.*proj.user
**/*.dbmdl
**/*.jfm
**/bin
**/charts
**/docker-compose*
**/Dockerfile*
**/node_modules
**/npm-debug.log
**/obj
**/secrets.dev.yaml
**/values.dev.yaml
**/.env
**/.env.local
**/.env.*.local
**/README.md
**/.DS_Store
```

**Why**:
- Smaller build context
- Faster builds
- Excludes sensitive files
- Better security

---

### Rule 4: Configure Health Checks

**Priority**: High

**Description**: Add health checks to Docker images for orchestration.

**Correct**:

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=publish /app/publish .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

**Why**:
- Enables container orchestration
- Automatic restart on failure
- Better monitoring
- Essential for Kubernetes

---

### Rule 5: Use Specific Base Images

**Priority**: High

**Description**: Use specific version tags, not latest.

**Incorrect**:

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:latest
# Latest can change unexpectedly
```

**Correct**:

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0
# Or even more specific
FROM mcr.microsoft.com/dotnet/aspnet:8.0.0
```

**Why**:
- Predictable builds
- Avoids breaking changes
- Better reproducibility
- Production stability

---

## Integration Example

Complete Dockerfile:

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restore dependencies
COPY ["MyApp.csproj", "./"]
RUN dotnet restore "MyApp.csproj"

# Build
COPY . .
RUN dotnet build "MyApp.csproj" -c Release -o /app/build

# Publish
FROM build AS publish
RUN dotnet publish "MyApp.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

COPY --from=publish /app/publish .
RUN chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

ENTRYPOINT ["dotnet", "MyApp.dll"]
```

## Checklist

- [ ] Multi-stage build used
- [ ] Layer caching optimized
- [ ] .dockerignore configured
- [ ] Health checks added
- [ ] Non-root user used
- [ ] Specific base image versions
- [ ] Security scanning enabled

## References

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [.NET Docker Images](https://hub.docker.com/_/microsoft-dotnet)

## Changelog

### v1.0.0
- Initial release
- 5 core rules for Docker containerization
