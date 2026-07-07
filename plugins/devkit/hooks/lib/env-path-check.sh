#!/usr/bin/env bash
# Shared .env path classification for devkit security hooks.
# Source this file; do not execute directly.

# Returns 0 if the path is a blocked .env file (secrets-bearing).
# Allows .env.example / .env.sample / .env.template.
devkit_is_blocked_env_path() {
  local file_path="$1"
  [[ "$file_path" == *".env"* ]] || return 1
  [[ "$file_path" != *".env.example"* ]] || return 1
  [[ "$file_path" != *".env.sample"* ]] || return 1
  [[ "$file_path" != *".env.template"* ]] || return 1
  return 0
}
