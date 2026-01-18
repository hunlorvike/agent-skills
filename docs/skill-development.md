# Skill Development Guide

This guide explains how to create new skills for the ASP.NET Agent Skills repository.

## Skill Structure

Every skill follows this structure:

```
skills/{category}/{skill-name}/
├── SKILL.md           # Required: Main skill definition
├── scripts/           # Optional: Automation scripts
│   └── analyze-*.ps1
└── references/        # Optional: Supporting docs
    └── *.md
```

## Creating a New Skill

### 1. Choose the Category

Select the appropriate category for your skill:

| Category | Description |
|----------|-------------|
| `api` | Web API design and routing |
| `auth` | Authentication & authorization |
| `data` | Data access & persistence |
| `observability` | Logging, tracing, monitoring |
| `testing` | Testing practices |
| `devops` | CI/CD and deployment |
| `security` | Security best practices |

### 2. Create the SKILL.md

Start with the template from `templates/SKILL-TEMPLATE.md`:

```yaml
---
name: your-skill-name
description: Brief description of the skill
version: 1.0.0
priority: critical|high|medium|low
categories:
  - primary-category
  - secondary-category
use_when:
  - "Clear trigger condition 1"
  - "Clear trigger condition 2"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Required packages"
related_skills:
  - other-skill-name
---

# Skill Name

## Overview

Detailed description...

## Rules

### Rule 1: Rule Title
...
```

### 3. Write Effective Rules

Each rule should have:

1. **Priority**: Critical, High, Medium, or Low
2. **Description**: What the rule enforces
3. **Incorrect Example**: Code to avoid
4. **Correct Example**: Code to follow
5. **Why**: Explanation of why this matters

Example:

```markdown
### Rule 1: Use appropriate HTTP status codes

**Priority**: Critical

**Description**: Return correct HTTP status codes for each operation.

**Incorrect**:
```csharp
[HttpGet("{id}")]
public async Task<IActionResult> GetOrder(int id)
{
    var order = await _repo.GetByIdAsync(id);
    return Ok(order); // Returns 200 even when null
}
```

**Correct**:
```csharp
[HttpGet("{id}")]
public async Task<ActionResult<OrderDto>> GetOrder(int id)
{
    var order = await _repo.GetByIdAsync(id);
    if (order is null)
        return NotFound();
    return Ok(order);
}
```

**Why**: Correct status codes are essential for RESTful APIs...
```

### 4. Add Automation Scripts (Optional)

Create PowerShell scripts that can analyze code:

```powershell
param(
    [string]$Path,
    [string]$OutputFormat = "console"
)

# Analysis logic here...

# Output in JSON format for tool integration
@{
    skill = "your-skill-name"
    summary = @{ critical = 0; high = 1; ... }
    issues = @(...)
} | ConvertTo-Json
```

### 5. Add Reference Documentation (Optional)

Include supporting documentation in `references/`:

- Quick reference guides
- Checklists
- Links to official docs
- Common patterns

## Best Practices

### Writing Rules

- Be specific and actionable
- Include real-world examples
- Explain the "why" behind each rule
- Link to official Microsoft documentation
- Test your examples compile

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Skill folder | kebab-case | `webapi-best-practices` |
| SKILL.md | UPPERCASE | `SKILL.md` |
| Scripts | kebab-case | `analyze-controllers.ps1` |

### Priority Guidelines

- **Critical**: Security issues, data loss, crashes
- **High**: Performance, maintainability, common bugs
- **Medium**: Code quality, conventions
- **Low**: Nice-to-have improvements

## Testing Your Skill

1. Validate YAML frontmatter syntax
2. Ensure code examples compile
3. Test any automation scripts
4. Have another developer review

## Submitting Your Skill

1. Fork the repository
2. Create a feature branch
3. Add your skill following this guide
4. Submit a pull request
5. Address review feedback

See [CONTRIBUTING.md](../CONTRIBUTING.md) for detailed contribution guidelines.
