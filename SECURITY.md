# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately:

1. **DO NOT** open a public GitHub issue
2. Use GitHub's private vulnerability reporting:
   - Go to https://github.com/teunlao/swift-ai-sdk/security/advisories
   - Click "Report a vulnerability"
3. Or email the maintainer directly (check GitHub profile)

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Time

- Initial response: Within 48 hours
- Status updates: Every 7 days
- Fix timeline: Depends on severity

## Security Best Practices

When using Swift AI SDK:

1. **API Keys**: Never commit API keys to source control
   - Use environment variables
   - Use secure key storage (Keychain on Apple platforms)

2. **Dependencies**: Keep the package updated
   ```bash
   swift package update
   ```

3. **Provider Configuration**:
   - Validate API responses
   - Set appropriate timeouts
   - Handle errors gracefully

4. **Data Handling**:
   - Don't log sensitive user data
   - Follow provider ToS and data policies
   - Implement proper access controls

## Known Security Considerations

- This SDK makes network requests to AI provider APIs
- API keys are required for provider access
- User prompts and responses are sent to third-party services
- Follow each provider's security and privacy policies

## Disclosure Policy

- Security issues will be disclosed after a fix is available
- CVE IDs will be requested for significant vulnerabilities
- Credit will be given to reporters (unless they prefer anonymity)
