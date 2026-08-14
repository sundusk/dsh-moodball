#!/bin/bash
# 开发模式：直接 swift run（无 .app 外壳，仍以 accessory 模式运行）
set -euo pipefail
cd "$(dirname "$0")"
exec swift run
