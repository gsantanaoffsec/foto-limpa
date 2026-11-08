#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/cache 'dist/Foto Limpa.app/Contents/MacOS'
xcrun swiftc -module-cache-path .build/cache -swift-version 5 -target arm64-apple-macosx13.0 -O -parse-as-library Sources/Cleaner.swift Sources/MetadataAudit.swift Sources/App.swift -o 'dist/Foto Limpa.app/Contents/MacOS/FotoLimpa'
cp Info.plist 'dist/Foto Limpa.app/Contents/Info.plist'
codesign --force --sign - 'dist/Foto Limpa.app'
echo 'Aplicativo criado em dist/Foto Limpa.app'
