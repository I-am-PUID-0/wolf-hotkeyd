# Security Policy

## Supported Versions

| Version / Branch | Supported |
|:-----------------|:---------:|
| `main` | Yes |
| Older tags | No |

## Reporting a Vulnerability

Do not open public issues for security reports.

Use GitHub's private vulnerability reporting:

1. Open the repository **Security** tab.
2. Click **Report a vulnerability**.
3. Include reproduction steps, impact, affected version or tag, and deployment
   assumptions.

If private reporting is unavailable, contact a maintainer directly and share
details privately.

## Response Targets

| Stage | Target |
|:------|:-------|
| Initial triage | Within 7 days |
| Status update after validation | Within 14 days |
| Fix timeline | Depends on severity and exploitability |

## Scope

This policy covers wolf-hotkeyd application code, action scripts, Docker image
scaffolding, release automation, and repository workflows.

Treat findings involving input event access, container escape paths, action
script command execution, process selection, or log exposure as
security-sensitive. Anti-cheat compatibility warnings are operational safety
issues, but this project does not provide anti-cheat bypasses or guarantees.
