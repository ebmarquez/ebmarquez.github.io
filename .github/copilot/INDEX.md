# 🤖 MCP Agents Documentation

Welcome to your expert team! This directory contains everything you need to work effectively with your four specialized MCP agents.

## 📚 Documentation Files

| File                                                 | Purpose                          | When to Use                        |
| ---------------------------------------------------- | -------------------------------- | ---------------------------------- |
| [**README.md**](./README.md)                         | Complete overview of all agents  | Start here! Learn about each agent |
| [**QUICK_REFERENCE.md**](./QUICK_REFERENCE.md)       | Copy-paste prompts               | Need a prompt template fast        |
| [**EXAMPLE_WORKFLOW.md**](./EXAMPLE_WORKFLOW.md)     | Multi-agent collaboration demo   | See agents working together        |
| [**BLOG_POST_TEMPLATE.md**](./BLOG_POST_TEMPLATE.md) | Blog post structure & checklist  | Creating a new blog post           |
| [**agents.json**](./agents.json)                     | Agent configurations (technical) | Customizing agent behavior         |

---

## 🎯 Quick Start

### First Time Here?

1. **Read**: [README.md](./README.md) - Meet your expert team
2. **Explore**: [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) - Try some prompts
3. **Learn**: [EXAMPLE_WORKFLOW.md](./EXAMPLE_WORKFLOW.md) - See agents in action
4. **Create**: [BLOG_POST_TEMPLATE.md](./BLOG_POST_TEMPLATE.md) - Write your first post

### Creating Your First Blog Post?

```
@workspace I'm writing a blog post about [topic]. Can you help me?

Tech Blogger: Create an engaging outline
Technical Editor: Review for clarity and accuracy  
Jekyll Expert: Format for Chirpy theme
DevOps Expert: Ensure smooth deployment
```

---

## 👥 Your Expert Team

### 🔧 DevOps & GitHub Actions Expert
**12 years experience** | GitHub Actions, CI/CD, automation
- [Quick prompts](./QUICK_REFERENCE.md#devops--github-actions-expert)
- Use for: Workflows, deployments, automation

### 💎 Jekyll Senior Developer  
**10 years experience** | Jekyll, Liquid, Chirpy theme
- [Quick prompts](./QUICK_REFERENCE.md#jekyll-senior-developer)
- Use for: Theme customization, Jekyll config, Liquid templates

### 📝 Senior Technical Editor
**15 years experience** | O'Reilly, Apress, Cisco, Microsoft Azure
- [Quick prompts](./QUICK_REFERENCE.md#senior-technical-editor)
- Use for: Content review, documentation, SEO, accuracy

### ✨ Technical Content Blogger
**10 years blogging** | Witty, fun, entertaining
- [Quick prompts](./QUICK_REFERENCE.md#technical-content-blogger)
- Use for: Engaging content, hooks, titles, storytelling

---

## 🚀 Common Tasks

### Writing a Blog Post
1. Open [BLOG_POST_TEMPLATE.md](./BLOG_POST_TEMPLATE.md)
2. Follow the multi-agent workflow from [EXAMPLE_WORKFLOW.md](./EXAMPLE_WORKFLOW.md)
3. Use the pre-publishing checklist

### Customizing the Chirpy Theme
1. Ask **Jekyll Expert** for the best approach
2. Consult **DevOps Expert** about upstream compatibility
3. Have **Technical Editor** document the change

### Troubleshooting GitHub Actions
1. Get **DevOps Expert** to analyze workflow logs
2. Ask **Jekyll Expert** if it's a build issue
3. Document the solution with **Technical Editor**

### Improving Existing Content
1. Have **Technical Editor** audit for quality
2. Get **Tech Blogger** to punch up engagement  
3. Ask **Jekyll Expert** about theme features to leverage

---

## 💡 Pro Tips

### Get Better Responses
- **Be specific**: Include file paths, error messages, or examples
- **Provide context**: Mention what you've tried or what you want to achieve
- **Use @workspace**: Reference your codebase for targeted help
- **Chain agents**: Use multiple experts for complex tasks

### Example of a Great Prompt
```
@workspace I'm getting a build error in my GitHub Actions workflow.

DevOps Expert: Review .github/workflows/pages-deploy.yml 
The error is: [paste error]
I've already tried: [what you tried]
Expected behavior: [what should happen]
```

### Example of Multi-Agent Collaboration
```
@workspace Help me optimize my blog for SEO:

Technical Editor: Audit all posts for SEO elements
Tech Blogger: Suggest engaging title improvements  
Jekyll Expert: Ensure Chirpy SEO features are configured
DevOps Expert: Set up automated sitemap generation
```

---

## 📖 Reference Materials

### Jekyll & Chirpy
- [Jekyll Docs](https://jekyllrb.com/docs/)
- [Chirpy Wiki](https://github.com/cotes2020/jekyll-theme-chirpy/wiki)
- [Liquid Syntax](https://shopify.github.io/liquid/)

### GitHub
- [GitHub Actions](https://docs.github.com/en/actions)
- [GitHub Pages](https://docs.github.com/en/pages)

### Writing
- [Microsoft Style Guide](https://docs.microsoft.com/en-us/style-guide/)
- [Google Dev Docs Style](https://developers.google.com/style)

---

## 🔄 Repository Context

All agents understand:
- **Type**: GitHub Pages blog with Jekyll
- **Theme**: [Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy)
- **Upstream**: One-way sync (pull only, never push)
- **Key Priority**: Maintain compatibility with upstream updates

---

## 🛠️ Customization

Want to modify your agents? Edit [agents.json](./agents.json):

```json
{
  "agents": [
    {
      "id": "agent-id",
      "name": "Agent Name",
      "systemPrompt": "Update this to change agent behavior",
      ...
    }
  ]
}
```

After editing, the changes take effect immediately in GitHub Copilot.

---

## 📋 Workflow Cheat Sheet

| I want to...        | Ask...                                          |
| ------------------- | ----------------------------------------------- |
| Write a blog post   | Tech Blogger → Technical Editor → Jekyll Expert |
| Fix a workflow      | DevOps Expert                                   |
| Customize theme     | Jekyll Expert → DevOps Expert                   |
| Improve content     | Technical Editor + Tech Blogger                 |
| Add automation      | DevOps Expert                                   |
| Review for accuracy | Technical Editor                                |
| Make content fun    | Tech Blogger                                    |
| SEO optimization    | Technical Editor + Jekyll Expert                |

---

## 🆘 Need Help?

### Stuck on something?
Try asking multiple agents from different perspectives:

```
@workspace I'm struggling with [problem].

DevOps Expert: Approach from automation perspective
Jekyll Expert: Approach from Jekyll/theme perspective  
Technical Editor: Is this a documentation/clarity issue?
```

### Want to see agents in action?
Check out [EXAMPLE_WORKFLOW.md](./EXAMPLE_WORKFLOW.md) for a complete example of all four agents collaborating on a blog post.

---

## 🎉 Ready to Go!

You now have a team of expert agents ready to help with:
- ✅ Writing engaging, accurate blog posts
- ✅ Customizing your Jekyll/Chirpy site
- ✅ Automating deployments with GitHub Actions  
- ✅ Maintaining high-quality technical content
- ✅ Optimizing for SEO and performance

**Start with**: [QUICK_REFERENCE.md](./QUICK_REFERENCE.md) for ready-to-use prompts!

---

*Questions? Try: `@workspace As [agent role], help me with [specific task]`*

*Last updated: December 18, 2025*
