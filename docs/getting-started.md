# Getting Started with ASP.NET Agent Skills

This guide helps you get started with using agent skills in your ASP.NET projects.

## What are Agent Skills?

Agent Skills are modular knowledge packs that help AI agents (and developers) understand and apply best practices when working with ASP.NET Core applications. Each skill contains:

- **Rules and Guidelines**: Specific best practices with correct/incorrect examples
- **Automation Scripts**: PowerShell scripts to analyze code (optional)
- **Reference Documentation**: Supporting materials and links

## Quick Start

### 1. Browse Available Skills

Skills are organized by category:

```
skills/
├── api/           # API design and routing
├── auth/          # Authentication & authorization
├── data/          # Data access & persistence
├── observability/ # Logging, tracing, monitoring
├── testing/       # Testing practices
├── devops/        # CI/CD and deployment
└── security/      # Security best practices
```

### 2. Read a Skill

Each skill has a `SKILL.md` file with:

```yaml
---
name: skill-name
description: What this skill covers
priority: critical|high|medium|low
use_when:
  - "When to apply this skill"
---

# Skill Name

## Rules

### Rule 1: Rule Title
**Priority**: Critical

**Incorrect**:
```csharp
// Bad example
```

**Correct**:
```csharp
// Good example
```

**Why**: Explanation...
```

### 3. Use the Skill Runner Tool

Install and run the skill runner:

```bash
# Install globally
dotnet tool install --global AspNet.SkillRunner

# List available skills
skill-runner list

# Check a project against a skill
skill-runner check webapi-best-practices --path ./src/MyApi

# Generate a full report
skill-runner report --path ./src/MyApi --output report.json
```

### 4. Integrate with AI Agents

Skills are designed for AI agents to consume. The `use_when` field in metadata helps agents determine when to activate a skill:

```yaml
use_when:
  - "When reviewing ASP.NET Web API controllers"
  - "When creating new REST endpoints"
```

## Skill Categories

### API & Routing
Best practices for designing RESTful APIs, including status codes, DTOs, pagination, and versioning.

### Authentication & Authorization
Secure your APIs with JWT, OAuth, and policy-based authorization.

### Data & Persistence
Optimize Entity Framework Core usage, avoid N+1 queries, and implement proper patterns.

### Observability
Implement structured logging, distributed tracing, and health checks.

### Testing
Write effective unit and integration tests with proper patterns.

### DevOps
Containerize applications and set up CI/CD pipelines.

### Security
Follow OWASP guidelines and implement security headers.

## Next Steps

1. [Browse the skills catalog](../skills/)
2. [Run the sample project](../samples/WebApiSample/)
3. [Contribute a new skill](./CONTRIBUTING.md)
