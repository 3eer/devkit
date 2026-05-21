# devkit OPA Policy
# Run with: conftest test --policy policies/devkit.rego .
# Requires: https://www.conftest.dev/

package devkit

import future.keywords.if
import future.keywords.in

# ---------------------------------------------------------------------------
# Deny list: known problematic npm packages
# Customize this list for your organization's requirements.
# ---------------------------------------------------------------------------
deny_packages := {
  "left-pad",       # famous removal incident
  "event-stream",   # supply chain attack (2018)
  "ua-parser-js",   # malware injection (2021)
  "node-ipc",       # malicious update targeting specific regions (2022)
  "colors",         # maintainer sabotage (2022)
  "faker",          # maintainer sabotage (2022)
  "coa",            # account hijack + malware (2021)
  "rc",             # account hijack + malware (2021)
  "eslint-scope",   # credentials theft (2018)
  "crossenv",       # typosquat malware
}

# Check package.json dependencies
deny[msg] if {
  input.file == "package.json"
  some pkg in object.keys(input.content.dependencies)
  pkg in deny_packages
  msg := sprintf("Denied package '%v' found in dependencies", [pkg])
}

deny[msg] if {
  input.file == "package.json"
  some pkg in object.keys(input.content.devDependencies)
  pkg in deny_packages
  msg := sprintf("Denied package '%v' found in devDependencies", [pkg])
}

# ---------------------------------------------------------------------------
# Warn: sensitive path changes require human review
# ---------------------------------------------------------------------------
sensitive_paths := {
  "infra/",
  "terraform/",
  "k8s/",
  ".github/workflows/",
  "secrets/",
  "certs/",
}

warn[msg] if {
  some path in sensitive_paths
  startswith(input.file, path)
  msg := sprintf("Sensitive path '%v' changed — human review recommended", [input.file])
}

# ---------------------------------------------------------------------------
# Deny: .env files must not be committed (allow .env.example / .env.sample / .env.template)
# ---------------------------------------------------------------------------
deny[msg] if {
  regex.match(`^(.*\/)?\.env(\.[a-z]+)?$`, input.file)
  not endswith(input.file, ".example")
  not endswith(input.file, ".sample")
  not endswith(input.file, ".template")
  msg := sprintf("'.env' file must not be committed: %v (use .env.example instead)", [input.file])
}

# ---------------------------------------------------------------------------
# Warn: private key files
# ---------------------------------------------------------------------------
warn[msg] if {
  regex.match(`\.(pem|key|p12|pfx)$`, input.file)
  msg := sprintf("Private key file detected: %v — ensure this is not a real private key", [input.file])
}
