# Security Policy

## Supported versions

Crazy File Manager is pre-1.0 and does not yet maintain multiple supported release lines. Only the latest commit on `main`, and the latest tagged release once tagged releases begin, receive security fixes. There is no backport policy for older tags at this time.

## Reporting a vulnerability

Please report suspected security vulnerabilities privately rather than opening a public issue.

- Preferred: use GitHub's private vulnerability reporting for this repository (Security tab → "Report a vulnerability"). This opens a private advisory visible only to the maintainer and the reporter.
- Include: a clear description of the issue, the affected version or commit, reproduction steps, and the potential impact.

Do not disclose the vulnerability publicly (issues, pull requests, forums, social media) until a fix has been released and coordinated disclosure has occurred.

## Response expectations

This is a solo/small-scale open-source project without a dedicated security team, so response times are best-effort, not a contractual SLA:

- Acknowledgement: typically within a few days of a report.
- Triage and severity assessment: as soon as practical after acknowledgement.
- Fix and disclosure timeline: communicated directly to the reporter once triage is complete, and coordinated with the reporter before any public disclosure.

## Scope

In scope: the Crazy File Manager application code in this repository, its build/release pipeline, and its update-check mechanism.

Out of scope: the underlying macOS operating system, Xcode/Apple system frameworks, and third-party infrastructure this project does not control (e.g. GitHub itself). Report those issues to Apple or the relevant vendor directly.

See `docs/security/threat-model.md` for the threats this project actively defends against, and `PRIVACY.md` for what data the application does and does not handle.
