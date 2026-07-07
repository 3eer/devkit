# devkit OPA Policy
# Run with: conftest test --combine --policy policies/devkit.rego .
# Requires: https://www.conftest.dev/
#
# --combine is required: input is an array of {path, contents} objects.

package main

import future.keywords.if
import future.keywords.in

# ---------------------------------------------------------------------------
# Deny list: known problematic npm packages (name-level blocklist).
# Prefer lockfile + npm audit / OSV for version-level coverage in CI.
# Customize for your organization.
# ---------------------------------------------------------------------------
blocked_packages := {
  "left-pad",
  "event-stream",
  "crossenv",
  "eslint-scope",
}

is_package_json(path) if {
  endswith(path, "package.json")
}

is_blocked_env_path(path) if {
  regex.match(`(^|.*/)\.env(\.[a-zA-Z0-9_-]+)?$`, path)
  not endswith(path, ".example")
  not endswith(path, ".sample")
  not endswith(path, ".template")
}

deny contains msg if {
  some i
  is_package_json(input[i].path)
  deps := object.get(input[i].contents, "dependencies", {})
  some pkg in object.keys(deps)
  pkg in blocked_packages
  msg := sprintf("Denied package '%v' found in %v dependencies", [pkg, input[i].path])
}

deny contains msg if {
  some i
  is_package_json(input[i].path)
  devdeps := object.get(input[i].contents, "devDependencies", {})
  some pkg in object.keys(devdeps)
  pkg in blocked_packages
  msg := sprintf("Denied package '%v' found in %v devDependencies", [pkg, input[i].path])
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

warn contains msg if {
  some i
  some prefix in sensitive_paths
  startswith(input[i].path, prefix)
  msg := sprintf("Sensitive path '%v' changed — human review recommended", [input[i].path])
}

# ---------------------------------------------------------------------------
# Deny: .env files must not be committed
# ---------------------------------------------------------------------------
deny contains msg if {
  some i
  is_blocked_env_path(input[i].path)
  msg := sprintf("'.env' file must not be committed: %v (use .env.example instead)", [input[i].path])
}

# ---------------------------------------------------------------------------
# Warn: private key files
# ---------------------------------------------------------------------------
warn contains msg if {
  some i
  regex.match(`\.(pem|key|p12|pfx)$`, input[i].path)
  msg := sprintf("Private key file detected: %v — ensure this is not a real private key", [input[i].path])
}
