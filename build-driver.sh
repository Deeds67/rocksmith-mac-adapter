#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
COMMIT=561d934c77a1fa64987e01ccabe890fed30e181f
if [ ! -d BlackHole ]; then
  git clone https://github.com/ExistentialAudio/BlackHole BlackHole
  git -C BlackHole checkout "$COMMIT"
fi
rm -rf build/BlackHole.driver build/RocksmithAdapter.driver
(cd BlackHole && xcodebuild -project BlackHole.xcodeproj -configuration Release -target BlackHole \
  CONFIGURATION_BUILD_DIR="$PWD/../build" \
  PRODUCT_BUNDLE_IDENTIFIER=audio.existential.RocksmithAdapter \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS kDriver_Name=\"RocksmithAdapter\" kPlugIn_BundleID=\"audio.existential.RocksmithAdapter\" kHas_Driver_Name_Format=false kDevice_Name=\"Rocksmith\ USB\ Guitar\ Adapter\" kNumber_Of_Channels=2 kSampleRates=48000')
mv build/BlackHole.driver build/RocksmithAdapter.driver
rm -rf build/BlackHole.driver.dSYM
codesign --force --deep -s - build/RocksmithAdapter.driver
echo "built: $PWD/build/RocksmithAdapter.driver"
