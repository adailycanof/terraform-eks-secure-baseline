#!/usr/bin/env bash
# Run `terraform init -backend=false && terraform validate` in every directory
# that contains .tf files, so modules are validated on their own and not just
# through the root that uses them.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

while IFS= read -r dir; do
  echo "::group::validate ${dir#"$root"/}"
  if ! (cd "$dir" && terraform init -backend=false -input=false -no-color >/dev/null && terraform validate -no-color); then
    echo "::error file=${dir#"$root"/}::terraform validate failed"
    failed=1
  fi
  echo "::endgroup::"
done < <(find "$root" -name '*.tf' -not -path '*/.terraform/*' -printf '%h\n' | sort -u)

exit "$failed"
