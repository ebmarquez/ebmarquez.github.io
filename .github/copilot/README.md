# MCP Agents for ebmarquez.github.io

This directory contains custom MCP (Model Context Protocol) agent configurations for your Jekyll blog built with the Chirpy theme.

## 🤖 Your Expert Team

### 1. DevOps & GitHub Actions Expert (`github-devops-expert`)
**Experience**: 12 years | **Role**: Senior DevOps Engineer

**Use when you need help with:**
- GitHub Actions workflows and automation
- CI/CD pipeline optimization
- GitHub Pages deployment issues
- Repository management and Git workflows
- Security and dependency updates
- Platform automation

**Example prompts:**
- "Can you review my GitHub Actions workflow for the pages deployment?"
- "How can I automate the process of pulling updates from the upstream Chirpy theme?"
- "Set up a workflow to check for broken links in my blog posts"

---

### 2. Jekyll Senior Developer (`jekyll-expert`)
**Experience**: 10 years | **Role**: Jekyll & Static Site Specialist

**Use when you need help with:**
- Jekyll configuration and customization
- Chirpy theme modifications
- Liquid templating and layouts
- Custom includes and plugins
- Performance optimization
- SEO improvements

**Example prompts:**
- "How do I customize the Chirpy theme without breaking upstream compatibility?"
- "Create a custom include for a featured post section"
- "Optimize my Jekyll build time"

---

### 3. Senior Technical Editor (`technical-editor`)
**Experience**: 15 years | **Education**: MA English - Stanford

**Background:**
- Senior Editor at O'Reilly Media (4 years)
- Editorial Director at Apress (4 years)  
- Documentation Lead at Cisco Systems (3 years)
- Senior Technical Writer at Microsoft Azure (4 years)

**Use when you need help with:**
- Reviewing blog posts for clarity and accuracy
- Improving technical documentation
- Style guide development
- Content structure and organization
- SEO optimization
- Front matter and metadata

**Example prompts:**
- "Review this draft blog post about Docker networking"
- "Help me improve the structure of this tutorial"
- "Create a style guide for my technical blog"

---

### 4. Technical Content Blogger (`tech-blogger`)
**Experience**: 10 years blogging | **Vibe**: Witty, fun, entertaining

**Known for**: Making complex tech topics accessible and entertaining (explaining Kubernetes using Mean Girls references, comparing BGP to The Bachelor)

**Use when you need help with:**
- Writing engaging blog posts
- Creating catchy titles and hooks
- Finding relatable analogies for complex topics
- Adding personality to technical content
- Content marketing and audience engagement
- Making dry topics sparkle

**Example prompts:**
- "Help me write an entertaining blog post about CI/CD pipelines"
- "Create a catchy title for my post about microservices"
- "Make this technical tutorial more engaging without losing accuracy"

---

## 🎯 How to Use These Agents

### In GitHub Copilot Chat

You can reference these agents by mentioning their expertise in your prompts:

```
@workspace As a DevOps expert, help me optimize my GitHub Actions workflow
```

```
@workspace As a Jekyll expert, how do I customize the Chirpy theme's sidebar?
```

```
@workspace As a technical editor, review this blog post draft
```

```
@workspace As a tech blogger, help me write an entertaining post about Kubernetes
```

### Agent Selection Guide

| Task                  | Recommended Agent               |
| --------------------- | ------------------------------- |
| GitHub Actions issues | DevOps Expert                   |
| Jekyll configuration  | Jekyll Expert                   |
| Theme customization   | Jekyll Expert                   |
| Workflow automation   | DevOps Expert                   |
| Blog post review      | Technical Editor                |
| Writing new content   | Tech Blogger                    |
| SEO optimization      | Technical Editor + Tech Blogger |
| Documentation         | Technical Editor                |
| Making content fun    | Tech Blogger                    |

---

## 📋 Repository Context

All agents understand:

- **Repository Type**: GitHub Pages blog with Jekyll
- **Theme**: Chirpy (`jekyll-theme-chirpy`)
- **Upstream**: https://github.com/cotes2020/jekyll-theme-chirpy.git
- **Sync Direction**: One-way (pull from upstream, never push back)
- **Key Constraint**: Customizations must be compatible with upstream updates

---

## 🛠️ Common Workflows

### Creating a New Blog Post

1. **Tech Blogger**: Draft the initial content with engaging hooks and analogies
2. **Technical Editor**: Review for accuracy, structure, and clarity
3. **Jekyll Expert**: Ensure proper front matter and Jekyll formatting
4. **DevOps Expert**: Verify the post builds correctly in CI/CD

### Customizing the Theme

1. **Jekyll Expert**: Identify the best approach for customization
2. **DevOps Expert**: Ensure changes won't conflict with upstream updates
3. **Technical Editor**: Document the customization for future reference

### Troubleshooting Build Issues

1. **DevOps Expert**: Check GitHub Actions logs and deployment
2. **Jekyll Expert**: Diagnose Jekyll-specific issues
3. **Technical Editor**: Update documentation based on resolution

---

## 📚 Additional Resources

### Jekyll & Chirpy
- [Jekyll Documentation](https://jekyllrb.com/docs/)
- [Chirpy Theme Docs](https://github.com/cotes2020/jekyll-theme-chirpy/wiki)
- [Liquid Syntax](https://shopify.github.io/liquid/)

### GitHub Actions
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub Pages Documentation](https://docs.github.com/en/pages)

### Technical Writing
- [Microsoft Style Guide](https://docs.microsoft.com/en-us/style-guide/)
- [Google Developer Documentation Style Guide](https://developers.google.com/style)

---

## 🔄 Maintaining Agent Configurations

The agent configurations are stored in [`agents.json`](./agents.json). You can:

- **Update system prompts** to refine agent behavior
- **Add new capabilities** as your needs evolve
- **Adjust expertise levels** based on your experience with each area

---

## 💡 Tips for Best Results

1. **Be specific**: The more context you provide, the better the response
2. **Use examples**: Share what you've tried or what similar results you want
3. **Iterate**: Start with one agent, then bring in others for different perspectives
4. **Combine expertise**: Don't hesitate to ask multiple agents about the same problem
5. **Reference files**: Use `@workspace` or specific file paths for targeted help

---

## 🤝 Contributing

Found ways to improve these agents? Update the [`agents.json`](./agents.json) file and document your changes here!

---

*Last updated: December 18, 2025*
