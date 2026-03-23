#!/bin/bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="${DEVELOPER_ID:-aerospace-codesign-certificate}"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

require-env() {
    local name="$1"
    if test -z "${!name:-}"; then
        echo "$name must be set to notarize the release" > /dev/stderr
        exit 1
    fi
}

notarize-release() {
    require-env APPLEID
    require-env APPLEIDPASS
    require-env TEAMID

    local notarization_dir=".release/notarization-submission"
    local notarization_zip=".release/notarization-submission.zip"

    rm -rf "$notarization_dir" "$notarization_zip"
    mkdir -p "$notarization_dir"
    cp -R .release/AeroSpace.app "$notarization_dir"
    cp -R .release/aerospace "$notarization_dir"

    ditto -c -k --keepParent "$notarization_dir" "$notarization_zip"

    xcrun notarytool submit "$notarization_zip" \
        --apple-id "$APPLEID" \
        --team-id "$TEAMID" \
        --password "$APPLEIDPASS" \
        --wait

    xcrun stapler staple .release/AeroSpace.app
    xcrun stapler validate .release/AeroSpace.app

    /usr/sbin/spctl -a -vv .release/AeroSpace.app
    codesign --check-notarization --verbose=4 .release/aerospace
}

should-notarize-release() {
    if test -n "${APPLEID:-}${APPLEIDPASS:-}${TEAMID:-}"; then
        require-env APPLEID
        require-env APPLEIDPASS
        require-env TEAMID
        return 0
    fi

    if ! grep -q SNAPSHOT <<< "$build_version"; then
        echo "APPLEID, APPLEIDPASS and TEAMID must be set in .env for non-SNAPSHOT release builds" > /dev/stderr
        exit 1
    fi

    return 1
}

#############
### BUILD ###
#############

./build-docs.sh
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh
./generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product aerospace -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

xcode_configuration="Release"
xcodebuild -version
xcodebuild-pretty .release/xcodebuild.log clean build \
    -scheme AeroSpace \
    -destination "generic/platform=macOS" \
    -configuration "$xcode_configuration" \
    -derivedDataPath .xcode-build

git checkout .

cp -r ".xcode-build/Build/Products/$xcode_configuration/AeroSpace.app" .release
cp -r .build/apple/Products/Release/aerospace .release

################
### SIGN APP ###
################

codesign --force -s "$codesign_identity" --entitlements ./resources/AeroSpace.entitlements \
    --options runtime --timestamp .release/AeroSpace.app/Contents/MacOS/AeroSpace
codesign --force -s "$codesign_identity" --options runtime --timestamp .release/AeroSpace.app

################
### SIGN CLI ###
################

codesign --force -s "$codesign_identity" --timestamp --options runtime .release/aerospace

################
### VALIDATE ###
################

expected_layout=$(cat <<EOF
.release/AeroSpace.app
.release/AeroSpace.app/Contents
.release/AeroSpace.app/Contents/_CodeSignature
.release/AeroSpace.app/Contents/_CodeSignature/CodeResources
.release/AeroSpace.app/Contents/MacOS
.release/AeroSpace.app/Contents/MacOS/AeroSpace
.release/AeroSpace.app/Contents/Resources
.release/AeroSpace.app/Contents/Resources/default-config.toml
.release/AeroSpace.app/Contents/Resources/AppIcon.icns
.release/AeroSpace.app/Contents/Resources/Assets.car
.release/AeroSpace.app/Contents/Info.plist
.release/AeroSpace.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/AeroSpace.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/AeroSpace.app
    exit 1
fi

check-universal-binary() {
    if ! file "$1" | grep --fixed-string -q "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64"; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/AeroSpace.app/Contents/MacOS/AeroSpace
check-universal-binary .release/aerospace

check-contains-hash .release/AeroSpace.app/Contents/MacOS/AeroSpace
check-contains-hash .release/aerospace

codesign -v .release/AeroSpace.app
codesign -v .release/aerospace

###################
### NOTARIZATION ###
###################

if should-notarize-release; then
    notarize-release
else
    echo "Skipping notarization for SNAPSHOT build"
fi

############
### PACK ###
############

mkdir -p ".release/AeroSpace-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-v$build_version/bin" && cp -r aerospace "AeroSpace-v$build_version/bin"
    cp -r AeroSpace.app "AeroSpace-v$build_version"
    zip -r "AeroSpace-v$build_version.zip" "AeroSpace-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospace aerospace-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AeroSpace-v$build_version.zip" \
        --build-version "$build_version"
done
