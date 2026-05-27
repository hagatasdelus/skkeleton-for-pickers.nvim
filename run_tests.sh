#!/bin/bash
set -e
echo "Running skkeleton-pickers.nvim tests..."
nvim --headless -u NONE -c "set rtp+=." -c "luafile spec/skkeleton-pickers_spec.lua"
