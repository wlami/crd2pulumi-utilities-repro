# crd2pulumi v1.6.1 `_utilities` import bug repro

Minimal repro for a platform-dependent bug in
[`pulumi/crd2pulumi`](https://github.com/pulumi/crd2pulumi) v1.6.1:
generated intermediate sub-package `__init__.py` files use
`from . import _utilities`, but `_utilities.py` is only emitted at the
top-level SDK package. Importing any leaf module fails with:

```
ImportError: cannot import name '_utilities' from 'pulumi_widgets.example'
```

## Run

```bash
go install github.com/pulumi/crd2pulumi@v1.6.1
export PATH="$HOME/go/bin:$PATH"
git clone https://github.com/wlami/crd2pulumi-utilities-repro
cd crd2pulumi-utilities-repro
bash repro.sh
```

## Status

| host | binary mod hash | result |
|------|-----------------|--------|
| Debian 13 arm64, Python 3.13.5 | `h1:mBiad7Wpj4b7SNbJiAuaOyeVZ4MA4LLpJfnGmGgqNkc=` | **REPRODUCED** |
| macOS 26.2 arm64, Python 3.12  | `h1:mBiad7Wpj4b7SNbJiAuaOyeVZ4MA4LLpJfnGmGgqNkc=` | does NOT repro |

Same crd2pulumi v1.6.1 source, identical mod hash, identical pulumi
codegen deps (`pulumi/pkg/v3 v3.216.0`,
`pulumi-kubernetes/provider/v4 v4.0.0-20260115033456-f47bc2d6f199`).
Generated relative-import depth differs by one level between platforms.
Output is deterministic per platform across multiple runs.

## What the bug looks like

Generated layout (Linux):

```
out/pulumi_widgets/
|- __init__.py            from . import _utilities    OK (top-level)
|- _utilities.py          <- only copy in the tree
|- example/
|  |- __init__.py         from . import _utilities    BROKEN
|  \- v1/
|     \- __init__.py      from .. import _utilities   OK
\- meta/
   |- __init__.py         from . import _utilities    BROKEN
   \- v1/
      \- __init__.py      from .. import _utilities   OK
```

On macOS the same generation produces `from .. import _utilities` at
the depth-1 sub-packages and `from ... import _utilities` at depth-2,
which works at runtime.

## Workaround (Linux)

Rewrite the depth-1 sub-package imports after generation:

```bash
find <sdk-root> -mindepth 3 -name __init__.py \
  -exec sed -i 's|^from \. import _utilities$|from .. import _utilities|' {} +
```

`-mindepth 3` from `<sdk-root>` skips the top-level package
`__init__.py` (which must keep `from . import _utilities`) and targets
only the intermediate sub-package files.
