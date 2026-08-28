#!/usr/bin/env python3
from pathlib import Path
import re

workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/build-dmg.yml").read_text()

assert re.search(r"(?m)^permissions:\n  contents: read$", workflow), (
    "workflow must default to contents: read"
)
assert re.search(r"(?ms)^  release:\n.*?^    if: startsWith\(github\.ref, 'refs/tags/v'\)", workflow), (
    "release publishing must be isolated in a tag-only job"
)
assert re.search(r"(?ms)^  release:\n.*?^    permissions:\n      contents: write$", workflow), (
    "only the release job may request contents: write"
)
assert "persist-credentials: false" in workflow, (
    "checkout must not persist the GitHub token for build scripts"
)

uses = re.findall(r"uses:\s+(actions/(?:checkout|upload-artifact|download-artifact))@([^\s]+)", workflow)
assert uses, "expected official actions in workflow"
for action, revision in uses:
    assert re.fullmatch(r"[0-9a-f]{40}", revision), (
        f"{action} must be pinned to an immutable 40-character commit SHA"
    )

print("workflow permission policy passed")
