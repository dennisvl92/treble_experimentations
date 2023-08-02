#!/bin/bash

rom_fp="$(date +%y%m%d)"
originFolder="$(dirname "$(readlink -f -- "$0")")"
mkdir -p release/$rom_fp/
set -e

if [ -z "$USER" ];then
	export USER="$(id -un)"
fi
export LC_ALL=C

build_target="$1"
rebuild_release=""
manifest_url="https://android.googlesource.com/platform/manifest"
aosp="android-11.0.0_r48"
phh="android-11.0"

if [ "$release" == true ];then
    [ -z "$version" ] && exit 1
    [ ! -f "$originFolder/release/config.ini" ] && exit 1
fi

if [ -n "$rebuild_release" ];then
	repo init -u "$tmp_manifest_source" -m manifest.xml --depth=1
else
	repo init -u "$manifest_url" -b $aosp --depth=1
	if [ -d .repo/local_manifests ] ;then
		( cd .repo/local_manifests; git fetch; git reset --hard; git checkout origin/$phh)
	else
		git clone https://github.com/dennisvl92/treble_manifest .repo/local_manifests -b $phh
	fi
fi
repo sync -c -j 1 --force-sync || repo sync -c -j1 --force-sync

repo forall -r '.*opengapps.*' -c 'git lfs fetch && git lfs checkout'
(cd device/phh/treble; git clean -fdx; if [ -f phh.mk ];then bash generate.sh phh;else bash generate.sh;fi)
(cd vendor/foss; git clean -fdx; bash update.sh)
if [ "$build_target" == "android-12.0" ] && grep -q lottie packages/apps/Launcher3/Android.bp;then
    (cd vendor/partner_gms; git am $originFolder/0001-Fix-SearchLauncher-for-Android-12.1.patch || true)
    (cd vendor/partner_gms; git am $originFolder/0001-Update-SetupWizard-to-A12.1-to-fix-fingerprint-enrol.patch || true)
fi
rm -f vendor/gapps/interfaces/wifi_ext/Android.bp

. build/envsetup.sh

buildVariant() {
	lunch $1
	make RELAX_USES_LIBRARY_CHECK=true BUILD_NUMBER=$rom_fp installclean
	make RELAX_USES_LIBRARY_CHECK=true BUILD_NUMBER=$rom_fp -j8 systemimage
	make RELAX_USES_LIBRARY_CHECK=true BUILD_NUMBER=$rom_fp vndk-test-sepolicy
	xz -c $OUT/system.img -T0 > release/$rom_fp/system-${2}.img.xz
}

repo manifest -r > release/$rom_fp/manifest.xml
bash "$originFolder"/list-patches.sh
cp patches.zip release/$rom_fp/patches-for-developers.zip

    (
        git clone https://github.com/phhusson/sas-creator
        cd sas-creator

        git clone https://github.com/phhusson/vendor_vndk -b android-10.0
    )

# ARM64 vanilla {ab, a-only, ab vndk lite}
#buildVariant treble_arm64_bvS-userdebug roar-arm64-ab-vanilla
#( cd sas-creator; bash run.sh 64 ; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-aonly-vanilla.img.xz)
#( cd sas-creator; bash lite-adapter.sh 64; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-ab-vndklite-vanilla.img.xz )

# ARM64 floss {ab, a-only, ab vndk lite}
#buildVariant treble_arm64_bfS-userdebug roar-arm64-ab-floss
##( cd sas-creator; bash run.sh 64 ; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-aonly-floss.img.xz)
#( cd sas-creator; bash lite-adapter.sh 64; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-ab-vndklite-floss.img.xz )

# ARM32 vanilla {ab, a-only}
#buildVariant treble_arm_bvS-userdebug roar-arm-ab-vanilla
#( cd sas-creator; bash run.sh 32; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm-aonly-vanilla.img.xz )

# ARM32 gogapps {ab, a-only}
#buildVariant treble_arm_boS-userdebug roar-arm-ab-gogapps
#( cd sas-creator; bash run.sh 32; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm-aonly-gogapps.img.xz )

# ARM32_binder64 vanilla {ab, ab vndk lite}
buildVariant treble_a64_bvS-userdebug roar-arm32_binder64-ab-vanilla
( cd sas-creator; bash lite-adapter.sh 32; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm32_binder64-ab-vndklite-vanilla.img.xz)

# ARM64 Gapps {ab, a-only, ab vndk lite}
#buildVariant treble_arm64_bgS-userdebug roar-arm64-ab-gapps
#( cd sas-creator; bash run.sh 64 ; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-aonly-gapps.img.xz)
#( cd sas-creator; bash lite-adapter.sh 64; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-ab-vndklite-gapps.img.xz )

# ARM32_binder64 go gapps {ab, ab vndk lite}
buildVariant treble_a64_boS-userdebug roar-arm32_binder64-ab-gogapps
( cd sas-creator; bash lite-adapter.sh 32; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm32_binder64-ab-vndklite-gogapps.img.xz )

# ARM32_binder64 gapps {ab, ab vndk lite}
buildVariant treble_a64_bgS-userdebug roar-arm32_binder64-ab-gapps
( cd sas-creator; bash lite-adapter.sh 32; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm32_binder64-ab-vndklite-gapps.img.xz )

if [ "$release" == true ];then
    (
        rm -Rf venv
        pip install virtualenv
        export PATH=$PATH:~/.local/bin/
        virtualenv -p /usr/bin/python3 venv
        source venv/bin/activate
        pip install -r $originFolder/release/requirements.txt

        name="AOSP 8.1"
        [ "$build_target" == "android-9.0" ] && name="AOSP 9.0"
        python $originFolder/release/push.py "$name" "$version" release/$rom_fp/
        rm -Rf venv
    )
fi
