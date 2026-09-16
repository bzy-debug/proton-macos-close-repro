#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec xcrun lldb --source reproduce.lldb \
  'dist/Proton Close Repro.app/Contents/MacOS/proton-close-repro'
