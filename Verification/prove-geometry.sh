#!/bin/zsh
set -e
HERE=${0:A:h}
VENV=${HERE:h}/.verify/tools/z3-venv
[[ -x $VENV/bin/python ]] || python3 -m venv $VENV
$VENV/bin/pip install -q --disable-pip-version-check --require-hashes -r $HERE/z3-requirements.txt
exec $VENV/bin/python -I $HERE/geometry.py "$@"
