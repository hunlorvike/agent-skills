# Contributing to ASP.NET Agent Skills

Thank you for your interest in contributing! This document provides guidelines for adding new skills or improving existing ones.

## Getting Started

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-skill-name`
3. Make your changes
4. Submit a pull request

## Adding a New Skill

### 1. Choose the Right Category

Skills are organized by category:
- `api/` - Web API design and routing
- `auth/` - Authentication and authorization
- `data/` - Data access and persistence
- `observability/` - Logging, tracing, monitoring
- `testing/` - Testing practices
- `devops/` - CI/CD and deployment
- `security/` - Security best practices

### 2. Create the Skill Structure

```
skills/{category}/{skill-name}/
├── SKILL.md           # Required: Main skill definition
├── scripts/           # Optional: Automation scripts
│   └── analyze-*.ps1
└── references/        # Optional: Supporting docs
    └── *.md
```

### 3. Write the SKILL.md

Use the template in `templates/SKILL-TEMPLATE.md`:

```yaml
---
name: skill-name
description: Brief description of the skill
version: 1.0.0
priority: critical|high|medium|low
categories:
  - category-name
use_when:
  - "Trigger condition 1"
  - "Trigger condition 2"
prerequisites:
  - "ASP.NET Core 8.0+"
---
```

### 4. Include Code Examples

Every rule should have:
- **Incorrect** code example (what to avoid)
- **Correct** code example (what to do)
- **Why** explanation (reasoning)

```markdown
### Rule 1: Rule Title
**Priority**: Critical

**Incorrect**:
```csharp
// Bad code example
```

**Correct**:
```csharp
// Good code example
```

**Why**: Clear explanation of why this matters...
```

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Skill folders | kebab-case | `webapi-best-practices` |
| Category folders | lowercase | `api`, `auth`, `data` |
| SKILL.md | UPPERCASE | `SKILL.md` |
| Scripts | kebab-case | `analyze-controllers.ps1` |
| C# files | PascalCase | `SkillRunner.cs` |

## Quality Guidelines

### Content Quality
- [ ] Clear, actionable rules
- [ ] Real-world code examples
- [ ] Proper C# syntax highlighting
- [ ] Links to official Microsoft documentation
- [ ] Tested examples that compile

### Technical Accuracy
- [ ] Following current ASP.NET Core best practices
- [ ] Compatible with .NET 8.0+
- [ ] No deprecated APIs or patterns
- [ ] Security considerations addressed

### Documentation
- [ ] Complete metadata in YAML frontmatter
- [ ] Clear `use_when` triggers
- [ ] Appropriate priority level
- [ ] References to official docs

## Pull Request Process

1. **Title**: `feat(category): Add skill-name skill`
2. **Description**: Explain the skill and its purpose
3. **Checklist**:
   - [ ] SKILL.md follows template
   - [ ] Code examples are correct
   - [ ] No linting errors
   - [ ] Tests pass (if applicable)

## Code of Conduct

- Be respectful and constructive
- Focus on technical accuracy
- Welcome feedback and suggestions
- Help others learn and improve

## Questions?

Open an issue with the `question` label for any questions about contributing.
