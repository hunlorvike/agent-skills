---
name: skill-name
description: Brief description of what this skill does and when to use it
version: 1.0.0
priority: critical|high|medium|low
categories:
  - api
  - security
use_when:
  - "When reviewing ASP.NET Web API controllers"
  - "When creating new REST endpoints"
  - "When refactoring existing API code"
prerequisites:
  - "ASP.NET Core 8.0+"
  - "Microsoft.AspNetCore.Mvc"
related_skills:
  - another-skill-name
---

# Skill Name

## Overview

Provide a detailed description of what this skill covers. Explain:
- The main purpose and goals
- Who should use this skill
- What problems it solves

## Rules

### Rule 1: Rule Title Here

**Priority**: Critical | High | Medium | Low

**Description**: Brief explanation of what this rule enforces.

**Incorrect**:

```csharp
// Example of what NOT to do
public class BadExample
{
    public void BadMethod()
    {
        // Problematic code here
    }
}
```

**Correct**:

```csharp
// Example of the correct approach
public class GoodExample
{
    public void GoodMethod()
    {
        // Proper implementation here
    }
}
```

**Why**: Explain why this matters. Include:
- Performance implications
- Security considerations
- Maintainability benefits
- Common mistakes this prevents

---

### Rule 2: Another Rule Title

**Priority**: High

**Description**: What this rule checks for.

**Incorrect**:

```csharp
// Bad example
```

**Correct**:

```csharp
// Good example
```

**Why**: Reasoning behind this rule.

---

## Integration Examples

### Example 1: Basic Implementation

Show a complete example of how to implement this skill's recommendations:

```csharp
// Complete working example
using Microsoft.AspNetCore.Mvc;

namespace MyApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ExampleController : ControllerBase
{
    // Implementation following all rules
}
```

### Example 2: Advanced Scenario

```csharp
// More complex example if needed
```

## Common Mistakes

1. **Mistake 1**: Description of common error
   - How to identify it
   - How to fix it

2. **Mistake 2**: Another common error
   - Identification
   - Resolution

## Checklist

Use this checklist when reviewing code:

- [ ] Check item 1
- [ ] Check item 2
- [ ] Check item 3
- [ ] Check item 4

## References

- [Microsoft Docs - Topic](https://docs.microsoft.com/aspnet/core/)
- [Related Blog Post](https://example.com)
- [GitHub Issue/Discussion](https://github.com)

## Changelog

### v1.0.0
- Initial release
- Added rules 1-N
