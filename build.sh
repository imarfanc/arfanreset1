#!/bin/zsh
# No uv, Deno, Python, Swift package manager, network or third-party libraries.
set -euo pipefail
cd "${0:A:h}"
mkdir -p build
app="$PWD/build/ArfanReset1.app"
rm -rf "$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
sdk=$(xcrun --sdk macosx --show-sdk-path)
sources=(Sources/*.swift)
compile() {
  xcrun swiftc -swift-version 5 -warnings-as-errors -O -sdk "$sdk" -target "$1-apple-macos14.0" \
    -framework AppKit -framework WebKit "${sources[@]}" -o "$2"
}
if [[ " ${*} " == *" --universal "* ]]; then
  compile arm64 build/ArfanReset1-arm64
  compile x86_64 build/ArfanReset1-x86_64
  lipo -create build/ArfanReset1-arm64 build/ArfanReset1-x86_64 -output "$app/Contents/MacOS/ArfanReset1"
else
  compile "$(uname -m)" "$app/Contents/MacOS/ArfanReset1"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
# Same pipeline as ArfanMenu3: multi-size TIFF, then tiff2icns. The artwork is a full-bleed square; macOS draws the icon shape.
rm -rf build/icon-tiff && mkdir -p build/icon-tiff
tiffs=()
for size in 16 32 64 128 256 512 1024; do
  sips -s format tiff -z $size $size Resources/ArfanReset1.png --out build/icon-tiff/icon-$size.tiff >/dev/null
  tiffs+=(build/icon-tiff/icon-$size.tiff)
done
tiffutil -catnosizecheck "${tiffs[@]}" -out build/icon-tiff/ArfanReset1.tiff
tiff2icns build/icon-tiff/ArfanReset1.tiff "$app/Contents/Resources/ArfanReset1.icns"
cp Resources/ArfanReset1.png "$app/Contents/Resources/ArfanReset1.png"
ditto Resources/Web "$app/Contents/Resources/Web"
ditto Resources/Config "$app/Contents/Resources/Config"
ditto Resources/Scripts "$app/Contents/Resources/Scripts"
ditto Resources/Functions "$app/Contents/Resources/Functions"
codesign --force --deep --sign - "$app"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict "$app"
if [[ " ${*} " == *" --selftest "* || " ${*} " == *" --zip "* ]]; then
  "$app/Contents/MacOS/ArfanReset1" --selftest
fi
if [[ " ${*} " == *" --zip "* ]]; then
  mkdir -p dist
  ditto -c -k --keepParent "$app" dist/ArfanReset1-26.10.2.zip
  print "Package: $PWD/dist/ArfanReset1-26.10.2.zip"
fi
if [[ " ${*} " == *" --install "* ]]; then
  ditto "$app" /Applications/ArfanReset1.app
  open /Applications/ArfanReset1.app
fi
print "Built: $app"
