#!/bin/bash

set -euo pipefail

exec /usr/bin/log stream \
  --style compact \
  --level debug \
  --predicate 'subsystem == "com.samsonlab.cinelark" OR (process == "IINA" AND eventMessage CONTAINS "[CineLark/")'
