#!/bin/bash

topdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# default options
arg_prefix=/usr/local
arg_tooldir=${topdir}/tools
arg_workdir=${topdir}/work
arg_logdir=
arg_config=${topdir}/build.conf
arg_schedule=

function usage () {
    echo "Usage: "
    echo "  build-setup.sh [OPTIONS]"
    echo
    echo "Setup a build machine for building flatpak."
    echo
    echo "This script will ensure all system dependencies are installed, build flatpak and some"
    echo "of it's dependencies and optionally schedule a cron job to automatically run the builds."
    echo
    echo "Note: This script will use sudo and prompt for a password"
    echo
    echo "Options:"
    echo
    echo "  -h --help                      Display this help message and exit"
    echo "  -p --prefix   <directory>      Install prefix for flatpak tooling (default: /usr/local)"
    echo "  -t --tooldir  <directory>      The directory to perform builds of system tooling in (default: 'tools' subdirectory)"
    echo "  -w --workdir  <directory>      The directory to perform builds in (default: 'work' subdirectory)"
    echo "  -l --logdir   <directory>      The directory in which to store build logs (default: Value of --workdir)"
    echo "  -c --config   <filename>       Alternative configuration file (default: build.conf in this directory)"
    echo "  -s --schedule <expression>     A cron expression indicating when the build should run (default: no cron jobs)"
    echo
}

while : ; do
    case "$1" in
	-h|--help)
	    usage;
	    exit 0;
	    shift ;;

	-p|--prefix)
	    arg_prefix=${2}
	    shift 2 ;;

	-t|--tooldir)
	    arg_tooldir=${2}
	    shift 2 ;;

	-w|--workdir)
	    arg_workdir=${2}
	    shift 2 ;;

	-l|--logdir)
	    arg_logdir=${2}
	    shift 2 ;;

	-c|--config)
	    arg_config=${2}
	    shift 2 ;;

	-s|--schedule)
	    arg_schedule=${2}
	    shift 2 ;;

	*)
	    break ;;
    esac
done

#
# Option sanity checks
#
mkdir -p "${arg_tooldir}" || dienow "Failed to create tools directory: ${arg_tooldir}"
mkdir -p "${arg_workdir}" || dienow "Failed to create work directory: ${arg_workdir}"
arg_prefix="$(cd ${arg_prefix} && pwd)"
arg_tooldir="$(cd ${arg_tooldir} && pwd)"
arg_workdir="$(cd ${arg_workdir} && pwd)"

if [ -z "${arg_logdir}" ]; then
    arg_logdir=${arg_workdir}
else
    arg_logdir="$(cd ${arg_logdir} && pwd)"
fi

if [ ! -f "${arg_config}" ]; then
    echo "Specified config file '${arg_config}' does not exist"
    echo
    usage
    exit 1
fi

# Make sure we have a full path to the configuration
arg_config="$(realpath $arg_config)"

# Prepare the build source logic, we're building in tooldir
# and installing into the prefix
build_source_workdir=${arg_tooldir}
build_source_prefix=${arg_prefix}

# Import the build source mechanics, the flatpak sources and the build config
. ${topdir}/include/build-source.sh
. ${topdir}/include/build-source-autotools.sh

#
# Packages required on Ubuntu 16.04
#
ubuntu_packages=(git build-essential python diffstat gawk chrpath texinfo bison unzip emacs
		 dh-autoreconf gobject-introspection gtk-doc-tools gnome-doc-utils
		 libattr1-dev libcap-dev libglib2.0-dev liblzma-dev e2fslibs-dev
		 libgpg-error-dev libgpgme11-dev libfuse-dev libarchive-dev
		 libgirepository1.0-dev libxau-dev libjson-glib-dev libpolkit-gobject-1-dev
		 libseccomp-dev elfutils libelf-dev libdwarf-dev libsoup2.4-dev)

#
# Sources that we build
#
buildSourceAdd "libgsystem" "git://git.gnome.org/libgsystem"                "master" buildInstallAutotools
buildSourceAdd "ostree"     "git://git.gnome.org/ostree"                    "master" buildInstallAutotools
buildSourceAdd "xdg-app"    "git://anongit.freedesktop.org/xdg-app/xdg-app" "master" buildInstallAutotools

function installPackages() {
    echo "Ensuring we have the packages we need..."
    sudo apt-get install "${ubuntu_packages[@]}"
}

function ensureBuildSchedule () {
    # Create the launch script based on our current configuration
    # and ensure that there is an entry in the user's crontab for
    # the launcher.
    #
    sed -e "s|@@TOPDIR@@|${topdir}|g" \
        -e "s|@@PREFIX@@|${build_source_prefix}|g" \
        -e "s|@@CONFIG@@|${arg_config}|g" \
        -e "s|@@WORKDIR@@|${arg_workdir}|g" \
        -e "s|@@LOGDIR@@|${arg_logdir}|g" \
	${topdir}/include/build-launcher.sh.in > ${topdir}/build-launcher.sh

    chmod +x ${topdir}/build-launcher.sh

    job="${arg_schedule} ${topdir}/build-launcher.sh"
    cat <(fgrep -i -v "build-launcher" <(crontab -l)) <(echo "$job") | crontab -
}

#
# Main
#
installPackages

buildSourceRun

# Scheduling the job is optional
if [ ! -z "${arg_schedule}" ]; then
    ensureBuildSchedule
fi
