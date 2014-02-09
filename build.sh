#!/bin/bash
#
# This script builds the archzfs packages in a clean clean chroot environment.
#
# For debug output, use DEBUG=1
# To show command output, but not do anything, use DRY_RUN=1
#
# This script requires clean-chroot-manager (https://github.com/graysky2/clean-chroot-manager)

# Defaults, don't edit these.
AZB_PKG_LIST="spl-utils spl zfs-utils zfs"
AZB_UPDATE_PKGBUILDS=""
AZB_BUILD=0
AZB_CHROOT_UPDATE=""
AZB_SIGN=""
AZB_CLEANUP=0

source ./lib.sh
source ./conf.sh

set -e

trap 'trap_abort' INT QUIT TERM HUP
trap 'trap_exit' EXIT

usage() {
	echo "build.sh - A build script for archzfs"
    echo
	echo "Usage: build.sh [options] [command [...]"
    echo
    echo "Options:"
    echo
    echo "    -h:    Show help information."
    echo "    -n:    Dryrun; Output commands, but don't do anything."
    echo "    -d:    Show debug info."
    echo "    -u:    Perform an update in the clean chroot."
    echo "    -C:    Remove all files that are not package sources."
    echo
    echo "Commands:"
    echo
    echo "    make      Build all packages."
    echo "    test      Build test packages."
    echo "    update    Update all PKGBUILDs using conf.sh variables."
    echo "    sign      GPG detach sign all compiled packages (default)."
    echo
	echo "Examples:"
    echo
    echo "    build.sh make -u          :: Update the chroot and build all of the packages"
    echo "    build.sh -C               :: Remove all compiled packages"
    echo "    build.sh update           :: Update PKGBUILDS only"
    echo "    build.sh update make -u   :: Update PKGBUILDs, update the chroot, and make all of the packages"
    echo "    build.sh update test -u   :: Update PKGBUILDs (use testing versions), update the chroot, and make all of the packages"
}

sed_escape_input_string() {
    echo "$1" | sed -e 's/[]\/$*.^|[]/\\&/g'
}

build_sources() {
    for PKG in $AZB_PKG_LIST; do
        msg "Building source for $PKG";
        run_cmd "cd \"$PWD/$PKG\""
        run_cmd "makepkg -Sfc"
        run_cmd "cd - > /dev/null"
    done
}

sign_packages() {
    if [[ $AZB_BUILD ]]; then
        FILES=$(find $PWD -iname "*${AZB_ZOL_VERSION}_${AZB_LINUX_VERSION}-${AZB_PKGREL}*.pkg.tar.xz")
    elif [[ $AZB_BUILD_TEST ]]; then
        FILES=$(find $PWD -iname "*${AZB_ZOL_VERSION}_${AZB_LINUX_TEST_VERSION}-${AZB_PKGREL}*.pkg.tar.xz")
    fi
    msg "Signing the packages with GPG"
    for F in $FILES; do
        msg2 "Signing $F"
        run_cmd "gpg --batch --yes --detach-sign --use-agent -u $AZB_GPG_SIGN_KEY \"$F\" &>/dev/null"
    done
}

update_pkgbuilds() {
    AZB_CURRENT_PKGVER=$(grep "pkgver=" zfs/PKGBUILD | cut -d= -f2 | cut -d_ -f1)
    AZB_CURRENT_PKGREL=$(grep "pkgrel=" zfs/PKGBUILD | cut -d= -f2)
    AZB_CURRENT_ZOLVER=$(sed_escape_input_string $AZB_CURRENT_PKGVER)
    AZB_CURRENT_SPL_DEPVER=$(grep "spl=" zfs/PKGBUILD | cut -d\" -f2 | cut -d= -f2)
    AZB_CURRENT_X32_LINUX_VERSION=$(grep "LINUX_VERSION_X32=" zfs/PKGBUILD | cut -d\" -f2)
    AZB_CURRENT_X64_LINUX_VERSION=$(grep "LINUX_VERSION_X64=" zfs/PKGBUILD | cut -d\" -f2)

    debug "AZB_CURRENT_PKGVER: $AZB_CURRENT_PKGVER"
    debug "AZB_CURRENT_PKGREL: $AZB_CURRENT_PKGREL"
    debug "AZB_CURRENT_ZOLVER: $AZB_CURRENT_ZOLVER"
    debug "AZB_CURRENT_SPL_DEPVER: $AZB_CURRENT_SPL_DEPVER"
    debug "AZB_CURRENT_X32_LINUX_VERSION: $AZB_CURRENT_X32_LINUX_VERSION"
    debug "AZB_CURRENT_X64_LINUX_VERSION: $AZB_CURRENT_X64_LINUX_VERSION"

    # Change the top level AZB_PKGREL
    run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \"s/pkgrel=$AZB_CURRENT_PKGREL/pkgrel=$AZB_PKGREL/g\""

    if [[ $AZB_BUILD ]]; then

        # Change the spl version number in zfs/PKGBUILD
        run_cmd "sed -i \"s/$AZB_CURRENT_SPL_DEPVER/$AZB_LINUX_FULL_VERSION/g\" zfs/PKGBUILD"

        # Change LINUX_VERSION_XXX
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \
            \"s/LINUX_VERSION_X32=\\\"$AZB_CURRENT_X32_LINUX_VERSION\\\"/LINUX_VERSION_X32=\\\"$AZB_LINUX_X32_VERSION_FULL\\\"/g\""
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \
            \"s/LINUX_VERSION_X64=\\\"$AZB_CURRENT_X64_LINUX_VERSION\\\"/LINUX_VERSION_X64=\\\"$AZB_LINUX_X64_VERSION_FULL\\\"/g\""

        # Replace the ZFS version
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \"s/$AZB_CURRENT_ZOLVER/$AZB_ZOL_VERSION/g\""

        # Replace the linux version in the top level PKGVER
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \"s/_$AZB_CURRENT_PKGVER/_$AZB_LINUX_VERSION/g\""

    elif [[ $AZB_BUILD_TEST ]]; then

        # Change the spl version number in zfs/PKGBUILD
        run_cmd "sed -i \"s/$AZB_CURRENT_SPL_DEPVER/$AZB_LINUX_TEST_FULL_VERSION/g\" zfs/PKGBUILD"

        # Change LINUX_VERSION_XXX
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \
            \"s/LINUX_VERSION_X32=\\\"$AZB_CURRENT_X32_LINUX_VERSION\\\"/LINUX_VERSION_X32=\\\"$AZB_LINUX_TEST_X32_VERSION_FULL\\\"/g\""
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \
            \"s/LINUX_VERSION_X64=\\\"$AZB_CURRENT_X64_LINUX_VERSION\\\"/LINUX_VERSION_X64=\\\"$AZB_LINUX_TEST_X64_VERSION_FULL\\\"/g\""

        # Replace the ZFS version
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \"s/$AZB_CURRENT_ZOLVER/$AZB_ZOL_VERSION/g\""

        # Replace the linux version in the top level PKGVER
        run_cmd "find . -iname \"PKGBUILD\" -print | xargs sed -i \"s/_$AZB_CURRENT_PKGVER/_$AZB_LINUX_TEST_VERSION/g\""

    fi

    # Update the sums of the files
    for PKG in $AZB_PKG_LIST; do
        run_cmd "updpkgsums $PKG/PKGBUILD"
    done
}

if [ $# -lt 1 ]; then
    usage;
    exit 0;
fi

ARGS=("$@")
for (( a = 0; a < $#; a++ )); do
    if [[ ${ARGS[$a]} == "make" ]]; then
        AZB_BUILD=1
    elif [[ ${ARGS[$a]} == "test" ]]; then
        AZB_BUILD_TEST=1
    elif [[ ${ARGS[$a]} == "update" ]]; then
        AZB_UPDATE_PKGBUILDS=1
    elif [[ ${ARGS[$a]} == "sign" ]]; then
        AZB_SIGN=1
    elif [[ ${ARGS[$a]} == "-h" ]]; then
        usage;
        exit 0;
    elif [[ ${ARGS[$a]} == "-u" ]]; then
        AZB_CHROOT_UPDATE="-u"
    elif [[ ${ARGS[$a]} == "-C" ]]; then
        AZB_CLEANUP=1
    elif [[ ${ARGS[$a]} == "-n" ]]; then
        DRY_RUN=1
    elif [[ ${ARGS[$a]} == "-d" ]]; then
        DEBUG=1
    fi
done

msg "build.sh started..."

if [[ $AZB_UPDATE_PKGBUILDS == 1 ]]; then
    update_pkgbuilds
fi

if [[ $AZB_SIGN == 1 ]]; then
    sign_packages
fi

if [[ $AZB_BUILD_TEST == 1 ]]; then
    if [ -n "$AZB_CHROOT_UPDATE" ]; then
        msg "Updating the i686 and x86_64 clean chroots..."
        run_cmd "sudo ccm32 u"
        run_cmd "sudo ccm64 u"
    fi
    for PKG in $AZB_PKG_LIST; do
        msg "Building $PKG..."
        run_cmd "cd \"$PWD/$PKG\""
        run_cmd "sudo ccm32 t"
        run_cmd "sudo ccm32 s"
        run_cmd "sudo ccm64 t"
        run_cmd "sudo ccm64 s"
        run_cmd "cd - > /dev/null"
    done
    build_sources
    sign_packages
fi
if [[ $AZB_BUILD == 1 ]]; then
    if [ -n "$AZB_CHROOT_UPDATE" ]; then
        msg "Updating the i686 and x86_64 clean chroots..."
        run_cmd "sudo ccm32 u"
        run_cmd "sudo ccm64 u"
    fi
    for PKG in $AZB_PKG_LIST; do
        msg "Building $PKG..."
        run_cmd "cd \"$PWD/$PKG\""
        run_cmd "sudo ccm32 s"
        run_cmd "sudo ccm64 s"
        run_cmd "cd - > /dev/null"
    done
    build_sources
    sign_packages
fi

if [[ $AZB_CLEANUP == 1 ]]; then
    msg "Cleaning up work files..."
    run_cmd "find . \( -iname \"*.log\" -o -iname \"*.pkg.tar.xz*\" -o -iname \"*.src.tar.gz\" -o -iname \"src\" \) -print -exec rm -rf {} \\;"
fi
