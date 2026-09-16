#!/bin/sh
set -eu
cd "$(dirname "$0")"
export PROTON_NO_UPDATE_CHECK=1
moonx moonbit-community/proton_cli@0.2.9 cef setup
moonx moonbit-community/proton_cli@0.2.9 package --format app
# Only this generated sample receives debugger permission.
codesign --force --sign - --options runtime --entitlements debug.entitlements \
  'dist/Proton Close Repro.app'
