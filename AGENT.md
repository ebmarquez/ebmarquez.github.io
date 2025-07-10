# Agent Instructions for ebmarquez.github.io

## Site Overview
This is Eric Marquez's personal blog and knowledge base, built with Jekyll using the Chirpy theme. The site covers technology, real estate, projects, food, and code snippets.

**Site URL:** https://ebmarquez.github.io  
**Theme:** Jekyll Chirpy  
**Owner:** Eric Marquez (ebmarquez)  
**Timezone:** America/Los_Angeles

## Content Guidelines

### General Rules
- Respect the existing content structure and style
- Follow Jekyll conventions and Chirpy theme guidelines
- Maintain consistency with the author's voice and technical writing style
- Always preserve existing metadata and frontmatter structure

### Post Creation Guidelines
- **Location:** All posts must be placed in `_posts/` directory
- **Naming:** Use format `YYYY-MM-DD-title-with-hyphens.md`
- **Frontmatter:** Include required fields:
  ```yaml
  ---
  layout: post
  title: Your Post Title
  date: YYYY-MM-DD HH:MM
  category: [technology|food|real-estate|projects|code]
  author: ebmarquez
  tags: [relevant, tags, here]
  summary: Brief description of the post
  ---
  ```

### Content Categories
- **Technology:** Technical tutorials, tools, software reviews
- **Real Estate:** Property projects, investment insights
- **Projects:** Personal and professional projects
- **Food:** Recipes and cooking adventures
- **Code:** Code snippets, programming tutorials

### Draft Management
- **Location:** Place drafts in `_drafts/` directory
- **Review:** Never publish drafts without explicit approval
- **Format:** Follow the same frontmatter structure as published posts

## Technical Guidelines

### File Structure
- `_posts/` - Published blog posts
- `_drafts/` - Unpublished drafts
- `_data/` - Structured data (authors, contact, media, etc.)
- `_includes/` - Reusable HTML components
- `_layouts/` - Page templates
- `_sass/` - Stylesheet files
- `assets/` - Static files (images, documents, etc.)

### Markdown Standards
- Use proper heading hierarchy (H1 for title, H2 for main sections)
- Include code blocks with language specification
- Use tables for structured data when appropriate
- Add alt text for images
- Include proper internal and external links

### Code Snippets
- Always specify language in fenced code blocks
- Include comments for clarity
- Test code before publishing
- Provide context and usage examples

## SEO and Performance

### Meta Requirements
- Every post must have a meaningful title and summary
- Use relevant tags (3-7 tags recommended)
- Include proper categories
- Ensure meta descriptions are compelling

### Image Guidelines
- Optimize images for web (compress when possible)
- Use descriptive filenames
- Include alt text for accessibility
- Store in appropriate subdirectories under `assets/`

## Accessibility Standards
- Use semantic HTML
- Provide alt text for images
- Ensure proper heading hierarchy
- Maintain good color contrast
- Test with screen readers when possible

## Security and Privacy
- Never include sensitive information (passwords, API keys, personal data)
- Sanitize any user-generated content
- Respect copyright and licensing
- Follow GitHub's community guidelines

### Tesla Fleet API Integration
- **Public Key Location:** Tesla public key must be accessible at `/.well-known/appspecific/com.tesla.3p.public-key.pem`
- **File Format:** PEM format with proper BEGIN/END markers
- **Content-Type:** Should be served as `application/x-pem-file` or `text/plain`
- **GitHub Actions:** Automated verification ensures file is included in builds
- **Home Assistant:** Enables Tesla Fleet integration via public key endpoint

## Automation Rules

### For AI Assistants
- When editing existing content, preserve the author's voice and style
- Always validate Jekyll syntax before suggesting changes
- Test locally when possible before publishing
- Respect the site's existing structure and conventions

### For Search Engines
- Respect `robots.txt` located in `assets/`
- Follow sitemap.xml guidelines
- Don't index draft content
- Respect meta robots directives

### For Content Management
- Regular backups are handled by GitHub
- Version control all changes
- Use meaningful commit messages
- Tag releases appropriately

## Contribution Workflow
1. Fork the repository
2. Create a feature branch
3. Make changes following these guidelines
4. Test locally with Jekyll
5. Submit pull request with clear description
6. Wait for review and approval

## Contact and Support
- GitHub Issues for bug reports and feature requests
- Pull Requests for contributions
- Discussions for general questions

## Tools and Dependencies
- **Jekyll:** Static site generator
- **Ruby:** Programming language for Jekyll
- **Bundler:** Dependency management
- **Node.js:** For build tools and JavaScript
- **GitHub Pages:** Hosting platform

## Quality Checklist
Before publishing any content, ensure:
- [ ] Proper frontmatter is included
- [ ] Content is well-structured with headings
- [ ] Code blocks have language specification
- [ ] Links are working and relevant
- [ ] Images are optimized and have alt text
- [ ] Spelling and grammar are correct
- [ ] Content fits the site's theme and audience
- [ ] Local Jekyll build is successful

---

*Last updated: July 8, 2025*
*For questions or updates to these instructions, please create an issue or pull request.*
