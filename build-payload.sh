#!/bin/bash

topdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# default options
build_source_workdir=${topdir}/work
build_source_force=false
build_source_arch=$(flatpak --default-arch)
build_source_target=

function usage () {
    echo "Usage: "
    echo "  build-payload.sh [OPTIONS]"
    echo
    echo "Builds the flatpack runtimes and apps in succession"
    echo
    echo "Options:"
    echo
    echo "  -h --help                      Display this help message and exit"
    echo "  -a --arch     <arch-name>      Host compatible cpu architecture to build for (default: The native arch)"
    echo "  -w --workdir  <directory>      The directory to perform builds in (default: 'work' subdirectory)"
    echo "  -t --target   <modulename>     Specify which module to process, otherwise processes all modules"
    echo "  -f --force                     Use brute force, sometimes wiping directories clean when required"
    echo
    echo "NOTE: Only host compatible architectures may be specified with --arch. Currently the supported"
    echo "      architectures include: i386, x86_64, aarch64 and arm. Use the --arch option to build a"
    echo "      32-bit arm runtime on an aarch64 host, or to build a 32bit i386 runtime on an x86_64 host."
    echo "  "
}

arg_workdir=
while : ; do
    case "$1" in
	-h|--help)
	    usage;
	    exit 0;
	    shift ;;

	-a|--arch)
	    build_source_arch=${2}
	    shift 2 ;;

	-w|--workdir)
	    arg_workdir=${2}
	    shift 2 ;;

	-t|--target)
	    build_source_target=${2}
	    shift 2 ;;

	-f|--force)
	    build_source_force=true
	    shift ;;

	*)
	    break ;;
    esac
done

# Get the absolute path to the work directory
#
if [ ! -z "${arg_workdir}" ]; then
    mkdir -p "${arg_workdir}" || dienow "Failed to create work directory: ${arg_workdir}"
    build_source_workdir="$(cd ${arg_workdir} && pwd)"
fi

# Import the build source mechanics, the flatpak sources and the build config
. ${topdir}/include/build-source.sh
. ${topdir}/include/build-source-flatpak.sh

# Declare arrays used in the config file
BASE_SDK_LIST=()
declare -A BASE_SDK_REPO
declare -A BASE_SDK_BRANCH
declare -A BASE_SDK_VERSION
declare -A BASE_SDK_ASSETS

SDK_LIST=()
declare -A SDK_REPO
declare -A SDK_BRANCH
declare -A SDK_VERSION
declare -A SDK_ASSETS

APP_LIST=()
declare -A APP_REPO
declare -A APP_BRANCH
declare -A APP_VERSION
declare -A APP_ASSETS

# Source the config, populate the various types of builds
. ${topdir}/build.conf

#
# Add the build sources defined in build.conf
#

#
# Base runtime
#
for src in "${BASE_SDK_LIST[@]}"; do
    buildSourceAdd "${src}" \
		   ${BASE_SDK_REPO["${src}"]} \
		   ${BASE_SDK_BRANCH["${src}"]} \
		   buildInstallFlatpakBase
done

#
# Sdks
#
for src in "${SDK_LIST[@]}"; do
    buildSourceAdd "${src}" \
		   ${SDK_REPO["${src}"]} \
		   ${SDK_BRANCH["${src}"]} \
		   buildInstallFlatpakSdk
done

#
# Apps
#
for src in "${APP_LIST[@]}"; do
    buildSourceAdd "${src}" \
		   ${APP_REPO["${src}"]} \
		   ${APP_BRANCH["${src}"]} \
		   buildInstallFlatpakApps
done


if [ ! -z "${build_source_target}" ]; then
    source_target_found=false
    for module in "${build_source_modules[@]}"; do
	if [ "${module}" == "${build_source_target}" ]; then
	    source_target_found=true;
	    break;
	fi
    done

    if ! $source_target_found; then
	echo "Specified target is not one of the modules defined in the configuration file."
	echo
	usage
	exit 1;
    fi
fi

#
# Run the build
#
buildSourceDownloadSources
buildSourceBuildSources
