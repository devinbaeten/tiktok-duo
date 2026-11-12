#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for suite in run run-cache run-glass run-native run-chrome run-shop; do
  sh "tests/$suite.sh"
done
python3 -m unittest discover -s tests -p 'test_*.py'
