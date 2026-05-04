#!/usr/bin/env bash
# Reproduce the crd2pulumi 1.6.1 _utilities import bug.
#
# Requirements:
#   - crd2pulumi 1.6.1 on PATH (or at $HOME/go/bin/crd2pulumi)
#   - python3 with pip
#
# What this does:
#   1. Generates a Python SDK from a minimal CRD using crd2pulumi.
#   2. Tries to import a sub-package of the generated SDK.
#   3. Fails with ImportError because sub-package __init__.py uses
#      `from . import _utilities` but _utilities.py only exists at
#      the top-level package.

set -euo pipefail

CRD2PULUMI="${CRD2PULUMI:-crd2pulumi}"
if ! command -v "$CRD2PULUMI" >/dev/null 2>&1; then
  if [ -x "$HOME/go/bin/crd2pulumi" ]; then
    CRD2PULUMI="$HOME/go/bin/crd2pulumi"
  else
    echo "ERROR: crd2pulumi not found. Install via:"
    echo "  go install github.com/pulumi/crd2pulumi/cmd/crd2pulumi@v1.6.1"
    exit 1
  fi
fi

echo "=== crd2pulumi version ==="
"$CRD2PULUMI" version || true
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

echo "Import succeeded. Bug not reproduced (or upstream fix shipped)."
