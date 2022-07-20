#!/bin/bash
export SWI_HOME_DIR="$SNAP/usr/lib/swi-prolog"
eval "$SNAP/terminusdb $@"
