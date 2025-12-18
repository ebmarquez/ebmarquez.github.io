# Quick Reference: MCP Agents

## 🚀 Quick Start

Copy and paste these prompts to get started with your expert agents!

---

## DevOps & GitHub Actions Expert

### Workflow Optimization
```
@workspace As a senior DevOps engineer with 12 years GitHub experience, review my GitHub Actions workflows in .github/workflows/ and suggest optimizations for speed and reliability.
```

### Automated Theme Updates
```
@workspace As a DevOps expert, help me create a GitHub Action that checks for updates from the upstream Chirpy theme repo and creates a PR when updates are available.
```

### Security Scanning
```
@workspace As a DevOps expert, set up automated security scanning for my Jekyll blog dependencies.
```

---

## Jekyll Senior Developer

### Theme Customization
```
@workspace As a Jekyll expert with 10 years experience, show me how to customize the Chirpy theme's [feature] without breaking compatibility with upstream updates.
```

### Performance Optimization
```
@workspace As a Jekyll expert, analyze my site's build performance and suggest optimizations.
```

### Custom Features
```
@workspace As a Jekyll expert, help me add [feature] to my Chirpy-based blog while maintaining the theme's architecture.
```

---

## Senior Technical Editor

### Blog Post Review
```
@workspace As a senior technical editor (O'Reilly, Microsoft Azure background), review my draft post at _posts/[filename].md for technical accuracy, clarity, and structure.
```

### Style Guide Creation
```
@workspace As a technical editor with Stanford MA in English, help me create a style guide for my technical blog covering tone, terminology, and formatting standards.
```

### SEO Optimization
```
@workspace As a technical documentation specialist, review and optimize the SEO elements (titles, descriptions, meta tags) across my blog posts.
```

---

## Technical Content Blogger

### Engaging Content Creation
```
@workspace As a witty tech blogger with 10 years experience, help me write an entertaining blog post about [topic] that makes it accessible and fun while staying technically accurate.
```

### Title Optimization
```
@workspace As a tech content blogger, create 10 catchy, SEO-friendly title options for my post about [topic].
```

### Hook Writing
```
@workspace As a tech blogger known for viral posts, write an engaging opening hook for my article about [topic] that grabs attention in the first 2 sentences.
```

---

## Multi-Agent Workflows

### Complete Blog Post Creation
```
@workspace I need to create a blog post about [topic]. 

1. Tech Blogger: Create an engaging outline with hooks and analogies
2. Technical Editor: Review and ensure accuracy and structure
3. Jekyll Expert: Format with proper front matter and Jekyll conventions
```

### Theme Customization Project
```
@workspace I want to add [feature] to my Chirpy theme.

1. Jekyll Expert: Recommend the best approach for this customization
2. DevOps Expert: Ensure it won't conflict with upstream updates
3. Technical Editor: Document the implementation
```

### Content Audit
```
@workspace Perform a content audit of my blog:

1. Technical Editor: Review all posts for consistency and quality
2. Tech Blogger: Suggest improvements for engagement
3. Jekyll Expert: Check for technical SEO issues
```

---

## Context Shortcuts

### Repository Info
```
This is a Jekyll blog forked from https://github.com/cotes2020/jekyll-theme-chirpy.git with one-way sync (pull only, never push back).
```

### Agent Roles Quick Reference

| Agent            | Call them for...                                     |
| ---------------- | ---------------------------------------------------- |
| DevOps Expert    | GitHub Actions, automation, deployments, CI/CD       |
| Jekyll Expert    | Theme customization, Liquid templates, Jekyll config |
| Technical Editor | Content review, documentation, style, accuracy       |
| Tech Blogger     | Engaging writing, hooks, titles, making content fun  |

---

## Pro Tips

1. **Start with context**: Always mention relevant file paths or describe what you're working on
2. **Be specific about the agent**: Use phrases like "As a [role]..." to activate the right persona
3. **Chain agents**: Use multiple agents in sequence for complex tasks
4. **Reference expertise**: Mention their background when you need that specific lens (e.g., "with your O'Reilly editing experience")
5. **Iterate**: Don't hesitate to ask follow-up questions or request revisions

---

## Example Session

```
User: @workspace As a Jekyll expert, I want to add a custom "featured posts" section to my homepage.

[Jekyll Expert provides implementation]

User: @workspace As a DevOps expert, will this customization conflict with future upstream updates from Chirpy?

[DevOps Expert analyzes compatibility]

User: @workspace As a technical editor, can you document this customization for future reference?

[Technical Editor creates documentation]
```

---

*Pro tip: Save your favorite prompts and build your own library of go-to commands!*
