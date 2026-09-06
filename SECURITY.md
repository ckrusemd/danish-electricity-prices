# Security policy

## Reporting a vulnerability

Please do not open a public issue for credentials, tokens, or other sensitive
information. Contact the repository owner privately through GitHub instead.

If a secret is ever committed, revoke or rotate it immediately. Removing the
file in a later commit is not sufficient because Git history remains available.

## Repository rules

- Do not commit `.env`, `Renviron.site`, credentials, tokens, private keys, or
  GitHub personal access tokens.
- Keep GitHub Actions permissions least-privilege.
- Use GitHub Actions secrets only when a feature genuinely requires them.
- Review dependency and workflow updates before merging them.
