# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 0.x     | Yes       |

## Reporting a Vulnerability

Please **do not** open a public issue for security vulnerabilities.

Email **isylla@softvalleylabs.com** with:

1. A description of the vulnerability and its potential impact.
2. Steps to reproduce or a proof-of-concept.
3. Any suggested mitigations you have in mind.

You will receive an acknowledgement within 48 hours. We aim to release a fix within 14 days for confirmed vulnerabilities.

## Scope

`dart_modernize` is a local CLI tool that reads and rewrites source files. It makes no network requests and stores no credentials. The main attack surfaces are:

- **Malicious pubspec.yaml / Dart source files** triggering unexpected behaviour in the analyzer.
- **Path traversal** via user-supplied project paths.

Reports outside this scope (e.g. phishing, social engineering) will not receive a response.
