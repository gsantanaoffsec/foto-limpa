#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/cache
xcrun swiftc -module-cache-path .build/cache -swift-version 5 Sources/Cleaner.swift Sources/MetadataAudit.swift Tests/main.swift -o .build/test-cleaner
.build/test-cleaner
