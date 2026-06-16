---
description: Validates and prepares a specific stage (infra, data, or apps) for deployment.
---

# Workflow: Deploy Homelab Stage
**Description:** Validates and prepares a specific stage (infra, data, or apps) for deployment.

## Steps
1. Navigate to the requested stage folder.
2. Validate the `compose.yml` syntax.
3. Check that the `homelab_net` is declared as external.
4. Verify that a `.env.example` file exists and `.env` is listed in `.gitignore`.
5. **Security Audit:** Scan modified files (e.g., `compose.yml`, scripts, diagrams) for hardcoded passwords, exact domain names, or absolute host paths. Ensure they are abstracted using environment variables (`${VARIABLE_NAME}`) or generic placeholders.
6. Call the `git-commits-fr` skill to prepare the commit message.