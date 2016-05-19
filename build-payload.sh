#!/bin/bash

topdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$(which flatpak)" ]; then
    echo "Flatpak is not installed or not available in PATH"
    exit 1
fi

# default options
arg_config=${topdir}/build.conf
arg_arch=
arg_workdir=${topdir}/work
arg_logdir=
arg_target=
arg_force=false

function usage () {
    echo "Usage: "
    echo "  build-payload.sh [OPTIONS]"
    echo
    echo "Builds the flatpack runtimes and apps in succession"
    echo
    echo "Options:"
    echo
    echo "  -h --help                      Display this help message and exit"
    echo "  -c --config   <filename>       Alternative configuration file (default: build.conf in this directory)"
    echo "  -a --arch     <arch-name>      Host compatible cpu architecture to build for (default: The native arch)"
    echo "  -w --workdir  <directory>      The directory to perform builds in (default: 'work' subdirectory)"
    echo "  -l --logdir   <directory>      Directory to log output of individual builds (default: stdout/stderr)"
    echo "  -t --target   <modulename>     Specify which module to process, otherwise processes all modules"
    echo "  -f --force                     Use brute force, sometimes wiping directories clean when required"
    echo
    echo "NOTE: Only host compatible architectures may be specified with --arch. Currently the supported"
    echo "      architectures include: i386, x86_64, aarch64 and arm. Use the --arch option to build a"
    echo "      32-bit arm runtime on an aarch64 host, or to build a 32bit i386 runtime on an x86_64 host."
    echo "  "
}

while : ; do
    case "$1" in
	-h|--help)
	    usage;
	    exit 0;
	    shift ;;

	-a|--arch)
	    arg_arch=${2}
	    shift 2 ;;

	-w|--workdir)
	    arg_workdir=${2}
	    shift 2 ;;

	-l|--logdir)
	    arg_logdir=${2}
	    shift 2 ;;

	-t|--target)
	    arg_target=${2}
	    shift 2 ;;

	-c|--config)
	    arg_config=${2}
	    shift 2 ;;

	-f|--force)
	    arg_force=true
	    shift ;;

	*)
	    break ;;
    esac
done

# Collect args and check them
#
mkdir -p "${arg_workdir}" || dienow "Failed to create work directory: ${arg_workdir}"
build_source_workdir="$(cd ${arg_workdir} && pwd)"

if [ ! -z "${arg_logdir}" ]; then
    mkdir -p "${arg_logdir}" || dienow "Failed to create log directory: ${arg_logdir}"
    build_source_logdir="$(cd ${arg_logdir} && pwd)"
fi

if [ ! -f "${arg_config}" ]; then
    echo "Specified config file '${arg_config}' does not exist"
    echo
    usage
    exit 1
fi

# Ensure the export directory just in case
mkdir -p "${arg_workdir}/export" || dienow "Failed to create export directory: ${arg_workdir}/export"

build_source_force=${arg_force}


#
# Declare arrays used in the config file
#
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
. ${arg_config}

# Resolve target architecture, which may be specified in the config
if [ ! -z "${arg_arch}" ]; then
    # From command line
    build_source_arch=${arg_arch}
elif [ ! -z "${BUILD_ARCH}" ]; then
    # From config file
    build_source_arch=${BUILD_ARCH}
else
    # Automatically guessed
    build_source_arch=$(flatpak --default-arch)
fi

#
# Import the build source mechanics once the config has been loaded
#
. ${topdir}/include/build-source.sh
. ${topdir}/include/build-source-flatpak.sh

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

#
# If the --target param was specified, assert that it's a valid
# module (now that they are all in build_source_modules[])
#
if [ ! -z "${arg_target}" ]; then
    source_target_found=false
    for module in "${build_source_modules[@]}"; do
	if [ "${module}" == "${arg_target}" ]; then
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

    build_source_target=${arg_target}
fi

#
# Run the build
#
buildSourceRun
