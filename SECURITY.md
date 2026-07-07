# Security Policy

MacMD is a local macOS Markdown editor. It has no network access, no analytics, and no background services, so its attack surface is limited to the files it opens and saves. Reports that fit that surface are taken seriously.

## Supported versions

MacMD is maintained by a single developer. Security fixes land in the latest release only.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No (please update) |

The current version is shown on the [latest release page](../../releases/latest) and in [CHANGELOG.md](CHANGELOG.md).

## Reporting a vulnerability

Please report security issues privately, not in a public issue.

Use GitHub's private reporting: open the **Security** tab of this repository and click **Report a vulnerability**. That opens a private advisory visible only to you and the maintainer.

If private reporting is unavailable, open a regular issue containing only the words "security report, please enable contact" with no further details, and wait to be contacted before sharing specifics.

Helpful details to include:

- The MacMD version (from the app's About window or the release tag).
- Your macOS version.
- A minimal Markdown file or sequence of steps that triggers the issue.
- What you observed (crash, hang, unexpected file write, and so on) and what you expected.

## Scope

In scope:

- Crashes, hangs, or excessive resource use triggered by opening or editing file content, for example a crafted line that makes syntax highlighting pathologically slow.
- Any path by which opening or saving a file could damage or overwrite data outside the file the user explicitly chose.
- Anything that allows file content to execute code.

Out of scope (these are documented design decisions, not vulnerabilities):

- The app is signed ad-hoc and is not Apple-notarized. The README covers the one-time first-launch Gatekeeper approval.
- The app is not sandboxed. The Security section of the README explains why.
- Issues that require an attacker to already have local access to your account, or to modify the installed app bundle.

## Response

This is a best-effort, single-maintainer project. Expect an initial acknowledgement within about a week. Confirmed issues are fixed in the next release, with credit in the changelog if you would like it.
