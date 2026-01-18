---
name: ci-cd-pipelines
description: Best practices for setting up CI/CD pipelines for ASP.NET Core applications using GitHub Actions, Azure DevOps, or other CI/CD platforms.
version: 1.0.0
priority: high
categories:
  - devops
  - cicd
  - automation
use_when:
  - "When setting up automated builds"
  - "When implementing deployment automation"
  - "When configuring CI/CD pipelines"
  - "When automating testing and deployment"
prerequisites:
  - "GitHub Actions, Azure DevOps, or similar"
  - "ASP.NET Core 8.0+"
related_skills:
  - docker-containerization
  - unit-testing
  - integration-testing
---

# CI/CD Pipelines Best Practices

## Overview

This skill covers best practices for creating CI/CD pipelines that build, test, and deploy ASP.NET Core applications automatically.

## Rules

### Rule 1: Run Tests in CI Pipeline

**Priority**: Critical

**Description**: Always run unit and integration tests in CI before deployment.

**Incorrect**:

```yaml
# GitHub Actions - no tests
name: Build
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-dotnet@v3
      - run: dotnet build
      - run: dotnet publish
      # No tests!
```

**Correct**:

```yaml
# GitHub Actions - with tests
name: CI
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup .NET
        uses: actions/setup-dotnet@v3
        with:
          dotnet-version: '8.0.x'
      
      - name: Restore dependencies
        run: dotnet restore
      
      - name: Build
        run: dotnet build --no-restore
      
      - name: Run unit tests
        run: dotnet test --no-build --verbosity normal --collect:"XPlat Code Coverage"
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.cobertura.xml
      
      - name: Run integration tests
        run: dotnet test --filter "Category=Integration" --no-build

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-dotnet@v3
        with:
          dotnet-version: '8.0.x'
      - run: dotnet publish -c Release -o ./publish
      - uses: actions/upload-artifact@v3
        with:
          name: publish
          path: ./publish
```

**Why**:
- Catches bugs early
- Prevents broken code in production
- Ensures code quality
- Required for reliable deployments

---

### Rule 2: Use Matrix Builds for Multiple Targets

**Priority**: Medium

**Description**: Test against multiple .NET versions and operating systems.

**Correct**:

```yaml
# Matrix strategy
strategy:
  matrix:
    dotnet-version: ['6.0', '7.0', '8.0']
    os: [ubuntu-latest, windows-latest]
    include:
      - dotnet-version: '8.0'
        os: ubuntu-latest
        publish: true

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        dotnet-version: ['6.0', '7.0', '8.0']
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-dotnet@v3
        with:
          dotnet-version: ${{ matrix.dotnet-version }}
      - run: dotnet test
```

**Why**:
- Ensures compatibility
- Tests cross-platform
- Better coverage
- Catches platform-specific issues

---

### Rule 3: Secure Secrets and Variables

**Priority**: Critical

**Description**: Never commit secrets. Use secure variables and secrets management.

**Incorrect**:

```yaml
# Secrets in workflow file - NEVER DO THIS
env:
  CONNECTION_STRING: "Server=prod;Database=MyDb;Password=secret123"
  API_KEY: "sk_live_1234567890"
```

**Correct**:

```yaml
# GitHub Actions - use secrets
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy to Azure
        uses: azure/webapps-deploy@v2
        with:
          app-name: 'my-app'
          publish-profile: ${{ secrets.AZURE_WEBAPP_PUBLISH_PROFILE }}
          package: ./publish
      
      - name: Set connection string
        run: |
          az webapp config connection-string set \
            --name my-app \
            --connection-string-type SQLAzure \
            --settings "DefaultConnection=${{ secrets.CONNECTION_STRING }}"
        env:
          AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
          AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

**Why**:
- Prevents secret exposure
- Secure credential management
- Compliance requirements
- Essential security practice

---

### Rule 4: Implement Deployment Stages

**Priority**: High

**Description**: Use staging environments before production deployment.

**Correct**:

```yaml
# Multi-stage deployment
jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Deploy to staging
        run: |
          # Deploy to staging environment
          az webapp deploy --name my-app-staging

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Deploy to production
        run: |
          # Deploy to production
          az webapp deploy --name my-app-prod
```

**Why**:
- Tests in production-like environment
- Reduces production failures
- Better deployment confidence
- Industry best practice

---

### Rule 5: Use Docker in CI/CD

**Priority**: High

**Description**: Build and push Docker images in CI pipeline.

**Correct**:

```yaml
jobs:
  build-docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Login to Container Registry
        uses: docker/login-action@v2
        with:
          registry: acr.azurecr.io
          username: ${{ secrets.ACR_USERNAME }}
          password: ${{ secrets.ACR_PASSWORD }}
      
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            acr.azurecr.io/myapp:${{ github.sha }}
            acr.azurecr.io/myapp:latest
          cache-from: type=registry,ref=acr.azurecr.io/myapp:buildcache
          cache-to: type=registry,ref=acr.azurecr.io/myapp:buildcache,mode=max
```

**Why**:
- Consistent builds
- Reproducible deployments
- Container orchestration ready
- Better deployment process

---

## Integration Example

Complete CI/CD pipeline:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-dotnet@v3
        with:
          dotnet-version: '8.0.x'
      - run: dotnet restore
      - run: dotnet build
      - run: dotnet test --collect:"XPlat Code Coverage"

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: dotnet publish -c Release

  deploy:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Deploy
        run: |
          # Deployment steps
```

## Checklist

- [ ] Tests run in CI
- [ ] Code coverage collected
- [ ] Secrets managed securely
- [ ] Multi-stage deployments
- [ ] Docker images built
- [ ] Artifacts published
- [ ] Deployment approvals configured

## References

- [GitHub Actions](https://docs.github.com/actions)
- [Azure DevOps Pipelines](https://docs.microsoft.com/azure/devops/pipelines/)

## Changelog

### v1.0.0
- Initial release
- 5 core rules for CI/CD pipelines
