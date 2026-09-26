#!/usr/bin/env bash
# Download beat-link and its runtime dependencies from Maven Central into ./lib.
# Run on the brain in ~/deckdash (deckdash compiles and runs against lib/*).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p lib
M=https://repo1.maven.org/maven2
for p in \
  org/deepsymmetry/beat-link/7.4.0/beat-link-7.4.0.jar \
  org/deepsymmetry/electro/0.1.4/electro-0.1.4.jar \
  org/deepsymmetry/crate-digger/0.2.0/crate-digger-0.2.0.jar \
  io/kaitai/kaitai-struct-runtime/0.10/kaitai-struct-runtime-0.10.jar \
  org/acplt/remotetea/remotetea-oncrpc/1.1.4/remotetea-oncrpc-1.1.4.jar \
  org/slf4j/slf4j-api/1.7.36/slf4j-api-1.7.36.jar \
  org/slf4j/slf4j-simple/1.7.36/slf4j-simple-1.7.36.jar \
  org/apache/commons/commons-math3/3.6.1/commons-math3-3.6.1.jar; do
  curl -sfL -o "lib/$(basename "$p")" "$M/$p"
done
ls lib
