#!/usr/bin/env bash
# Reproduce the crd2pulumi 1.6.1 _utilities import bug.
#
# Bug is platform-dependent:
#   - Repros on Linux (e.g. Debian 13 arm64, Python 3.13)
#   - Does NOT repro on macOS arm64 with the same crd2pulumi v1.6.1
#     binary built from source. This script will print
#     "Import succeeded" on macOS - that is expected.
#
# Requirements:
#   - crd2pulumi 1.6.1 on PATH (or at $HOME/go/bin/crd2pulumi)
#   - python3 with pip
#
# What this does:
#   1. Captures host + binary identity so the result is unambiguous.
#   2. Generates a Python SDK from a minimal CRD using crd2pulumi.
#   3. Tries to import a sub-package of the generated SDK.
#   4. On Linux: fails with ImportError because sub-package __init__.py
#      uses `from . import _utilities` but _utilities.py only exists at
#      the top-level package.

set -euo pipefail

CRD2PULUMI="${CRD2PULUMI:-crd2pulumi}"
if ! command -v "$CRD2PULUMI" >/dev/null 2>&1; then
  if [ -x "$HOME/go/bin/crd2pulumi" ]; then
    CRD2PULUMI="$HOME/go/bin/crd2pulumi"
  else
    echo "ERROR: crd2pulumi not found. Install via:"
    echo "  go install github.com/pulumi/crd2pulumi@v1.6.1"
    exit 1
  fi
fi

CRD2PULUMI_ABS="$(command -v "$CRD2PULUMI")"

echo "=== environment ==="
uname -a
python3 --version
echo

echo "=== crd2pulumi binary identity ==="
echo "path: $CRD2PULUMI_ABS"
"$CRD2PULUMI" version || true
if command -v go >/dev/null 2>&1; then
  go version -m "$CRD2PULUMI_ABS" 2>/dev/null \
    | grep -E '^[[:space:]]*(path|mod)[[:space:]]+' || true
fi
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$CRD2PULUMI_ABS"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$CRD2PULUMI_ABS"
fi
echo

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WORKDIR"

rm -rf out venv

echo "=== generating SDK ==="
"$CRD2PULUMI" --pythonPath out --pythonName widgets crd.yaml
echo

echo "=== generated layout ==="
find out -name '__init__.py' | sort
echo

echo "=== top-level __init__.py (line with _utilities) ==="
grep -nH '_utilities' out/pulumi_widgets/__init__.py || true
echo

echo "=== sub-package __init__.py (line with _utilities) ==="
grep -rnH '_utilities' out/pulumi_widgets/example/ out/pulumi_widgets/meta/ || true
echo

echo "=== installing into a fresh venv ==="
python3 -m venv venv
# shellcheck disable=SC1091
source venv/bin/activate
pip install --quiet -e ./out

echo
echo "=== attempting import ==="
set +e
python -c "import pulumi_widgets.example.v1; print('import OK')" 2>&1
RC=$?
set -e
deactivate

if [ $RC -ne 0 ]; then
  echo
  echo "REPRODUCED. Sub-package import fails because"
  echo '  out/pulumi_widgets/example/__init__.py'
  echo "uses 'from . import _utilities' but _utilities.py lives at"
  echo '  out/pulumi_widgets/_utilities.py'
  echo "(one level up). The correct relative import is 'from .. import _utilities'."
  exit 0
fi

echo "Import succeeded."
echo "Expected on macOS - bug is platform-specific. On Linux this means"
echo "either the upstream fix shipped or your binary differs from v1.6.1."
