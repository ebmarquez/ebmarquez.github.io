# Example: Multi-Agent Blog Post Workflow

This example demonstrates how all four expert agents work together to create, refine, and publish a high-quality technical blog post.

## Scenario: Writing a Blog Post About GitHub Actions

---

## Phase 1: Ideation & Outline

### 🎨 Tech Blogger (Initial Draft)

**Prompt:**
```
@workspace As a witty tech blogger with 10 years experience, help me create an engaging blog post about GitHub Actions for beginners. Make it fun and accessible!
```

**Output:**
```markdown
Title: "GitHub Actions: Or How I Learned to Stop Worrying and Love Automation"

Hook: Remember when deploying code felt like defusing a bomb? One wrong move and boom—production goes down, your phone explodes with alerts, and suddenly you're the villain in your own disaster movie. GitHub Actions is here to make sure your deployments are more "boring success" and less "Michael Bay film."

Outline:
1. What is GitHub Actions? (The "dating profile" version)
2. Why should you care? (The FOMO is real)
3. Your first workflow (We'll hold your hand)
4. Real-world example (Blog deployment, because meta)
5. Common gotchas (So you don't have to learn the hard way)
6. Conclusion (You're basically a DevOps engineer now)
```

---

## Phase 2: Technical Review

### 📝 Technical Editor (Content Review)

**Prompt:**
```
@workspace As a senior technical editor with O'Reilly and Microsoft Azure experience, review this blog post outline and initial draft for technical accuracy and structure.
```

**Feedback:**
```
STRENGTHS:
✓ Engaging hook that resonates with developer pain points
✓ Logical progression from concept to implementation
✓ Relatable tone while maintaining professionalism

RECOMMENDATIONS:

1. Structure:
   - Add a "Prerequisites" section before the first workflow
   - Include a "Further Reading" section at the end
   - Consider adding a troubleshooting subsection

2. Technical Accuracy:
   - Define "workflow," "action," and "runner" clearly in section 1
   - Ensure YAML examples follow best practices
   - Include actual timing/cost considerations for Actions

3. Content Gaps:
   - Mention secrets management
   - Discuss workflow permissions
   - Add note about Actions marketplace

4. Front Matter:
   - Add relevant tags: [github, ci-cd, automation, devops, tutorial]
   - Category: DevOps or Automation
   - Ensure SEO description summarizes key benefits
   - Add estimated read time

5. SEO Optimization:
   - Title is catchy but consider adding "Tutorial" for search
   - Meta description should include "GitHub Actions tutorial"
   - Add internal links to related posts if available
```

---

## Phase 3: Jekyll Implementation

### 🔧 Jekyll Expert (Technical Implementation)

**Prompt:**
```
@workspace As a Jekyll expert with 10 years experience, help me properly format this blog post for my Chirpy theme, including front matter, code blocks, and any theme-specific features I should use.
```

**Output:**
```markdown
---
title: "GitHub Actions: Or How I Learned to Stop Worrying and Love Automation"
date: 2025-12-18 10:00:00 -0500
categories: [DevOps, Automation]
tags: [github, github-actions, ci-cd, automation, devops, tutorial, beginners]
description: "A beginner-friendly guide to GitHub Actions that makes automation fun and accessible. Learn to automate your deployments without the headaches."
image:
  path: /assets/img/posts/github-actions-hero.png
  alt: "GitHub Actions workflow visualization"
author: ebmarquez
pin: false
math: false
mermaid: true
---

## What is GitHub Actions?

Think of GitHub Actions as your personal robot army that lives inside GitHub...

## Your First Workflow

Let's create a simple workflow. In your repository, create this file:

```yaml
# .github/workflows/hello-world.yml
name: Hello World

on:
  push:
    branches: [ main ]

jobs:
  greet:
    runs-on: ubuntu-latest
    steps:
      - name: Say hello
        run: echo "Hello, GitHub Actions!"
```
{: file='.github/workflows/hello-world.yml'}

> **Note:** This workflow runs every time you push to the main branch.
{: .prompt-info }

## Common Gotchas

⚠️ **Secrets in workflows**: Never hardcode API keys!

```yaml
# ❌ DON'T DO THIS
- name: Deploy
  run: deploy.sh --api-key=abc123

# ✅ DO THIS
- name: Deploy
  run: deploy.sh --api-key=${{ secrets.API_KEY }}
```

## Further Reading

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Actions Marketplace](https://github.com/marketplace?type=actions)
- [Our post on CI/CD Best Practices](#)

---

CHIRPY THEME FEATURES USED:
1. File path annotations: `{: file='...'}`
2. Prompt boxes: `{: .prompt-info }`, `{: .prompt-warning }`
3. Mermaid diagrams: Set `mermaid: true` in front matter
4. Image with alt text in front matter
5. Author attribution
6. Pin option for featured posts
7. Table of contents (automatic)
8. Code syntax highlighting with language tags
```

---

## Phase 4: Deployment & Automation

### ⚙️ DevOps Expert (CI/CD Review)

**Prompt:**
```
@workspace As a DevOps expert with 12 years GitHub experience, review how this blog post will be deployed through our GitHub Actions workflow and ensure everything is optimized.
```

**Analysis:**
```
DEPLOYMENT REVIEW:

✅ Current Setup (from .github/workflows/pages-deploy.yml):
- Triggered on push to main
- Builds Jekyll site
- Deploys to GitHub Pages
- Caches dependencies

RECOMMENDATIONS:

1. Pre-deployment Checks:
   Add a workflow to validate blog posts before merging:

   ```yaml
   name: Validate Blog Post
   on:
     pull_request:
       paths:
         - '_posts/**'
   
   jobs:
     validate:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         
         - name: Check front matter
           run: |
             for file in _posts/*.md; do
               if ! grep -q "^---" "$file"; then
                 echo "Missing front matter in $file"
                 exit 1
               fi
             done
         
         - name: Check for broken links
           uses: gaurav-nelson/github-action-markdown-link-check@v1
         
         - name: Spell check
           uses: rojopolis/spellcheck-github-actions@0.5.0
   ```

2. Build Optimization:
   - ✅ Already caching gems (good!)
   - Consider caching npm dependencies
   - Add build time reporting

3. Post-deployment:
   - Add a smoke test to verify the post is live
   - Consider automated social media posting
   - Set up Google Search Console auto-submission

4. This Blog Post Specifically:
   - Ensure the workflow example in the post uses latest action versions
   - Verify all YAML is valid before publishing
   - The meta-irony of using GitHub Actions to deploy a post about GitHub Actions? *chef's kiss*

COMPATIBILITY NOTE:
Since you're pulling from upstream Chirpy, ensure any workflow modifications are in custom files (not overriding theme defaults) to avoid merge conflicts.
```

---

## Phase 5: Final Polish

### Multi-Agent Review

**Prompt:**
```
@workspace Before publishing this GitHub Actions blog post:

1. Tech Blogger: Is it engaging enough? Any final touches?
2. Technical Editor: Final accuracy and SEO check
3. Jekyll Expert: Verify Chirpy theme integration
4. DevOps Expert: Confirm deployment readiness
```

**Final Checklist:**

- [x] **Engaging & Accessible** (Tech Blogger) ✓
- [x] **Technically Accurate** (Technical Editor) ✓
- [x] **Properly Formatted** (Jekyll Expert) ✓
- [x] **Deploy-Ready** (DevOps Expert) ✓

---

## Result

A high-quality blog post that is:
- **Entertaining** (Tech Blogger magic)
- **Accurate** (Technical Editor rigor)
- **Well-Formatted** (Jekyll Expert precision)
- **Automated** (DevOps Expert efficiency)

---

## Key Takeaways

1. **Start creative, then refine**: Tech Blogger gets creative freedom, then experts polish
2. **Technical accuracy matters**: Editor catches issues before they go live
3. **Use theme features**: Jekyll Expert knows all the Chirpy tricks
4. **Automate everything**: DevOps Expert ensures smooth deployment

---

## Your Turn!

Try this workflow with your next blog post:

1. Brainstorm with **Tech Blogger**
2. Review with **Technical Editor**
3. Format with **Jekyll Expert**
4. Deploy with **DevOps Expert**

Happy blogging! 🚀
