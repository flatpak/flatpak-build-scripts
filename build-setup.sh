#!/bin/bash

topdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# default options
arg_workdir=
arg_logdir=
arg_prefix=/usr/local
arg_cron="0 0 * * *"

function usage () {
    echo "Usage: "
    echo "  build-setup.sh [OPTIONS]"
    echo
    echo "Build and install dependencies required for building the flatpak SDKs and application bundles"
    echo
    echo "Options:"
    echo
    echo "  -h --help                      Display this help message and exit"
    echo "  -p --prefix   <directory>      Install prefix for flatpak tooling (default: /usr/local)"
    echo "  -w --workdir  <directory>      The directory to perform builds in (default: 'work' subdirectory)"
    echo "  -l --logdir   <directory>      The directory in which to store build logs (default: Value of --workdir)"
    echo "  -c --cron     <expression>     A cron expression indicating when the build should run (default: every day at Midnight)"
    echo
}

while : ; do
    case "$1" in
	-h|--help)
	    usage;
	    exit 0;
	    shift ;;

	-a|--arch)
	    arg_prefix=${2}
	    shift 2 ;;

	-w|--workdir)
	    arg_workdir=${2}
	    shift 2 ;;

	-l|--logdir)
	    arg_logdir=${2}
	    shift 2 ;;

	-c|--cron)
	    arg_cron=${2}
	    shift 2 ;;

	*)
	    break ;;
    esac
done

# Get the absolute path to the work directory and install prefix
#
if [ ! -z "${arg_workdir}" ]; then
    mkdir -p "${arg_workdir}" || dienow "Failed to create work directory: ${arg_workdir}"
    build_source_workdir="$(cd ${arg_workdir} && pwd)"
fi

if [ ! -z "${arg_prefix}" ]; then
    mkdir -p "${arg_prefix}" || dienow "Failed to create install prefix: ${arg_prefix}"
    build_source_prefix="$(cd ${arg_prefix} && pwd)"
fi

if [ -z "${arg_logdir}" ]; then
    arg_logdir=${build_source_workdir}
else
    arg_logdir="$(cd ${arg_logdir} && pwd)"
fi

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
buildSourceAdd "libgsystem" "git://git.gnome.org/libgsystem"          "master" buildInstallAutotools
buildSourceAdd "ostree"     "git://git.gnome.org/ostree"              "master" buildInstallAutotools
buildSourceAdd "xdg-app"    "https://github.com/gtristan/xdg-app.git" "master" buildInstallAutotools

function installPackages() {
    echo "Ensuring we have the packages we need..."
    sudo apt-get install "${ubuntu_packages[@]}"
}

function ensureUpdateCron () {
    # Create the launch script based on our current configuration
    # and ensure that there is an entry in the user's crontab for
    # the launcher.
    #
    sed -e "s|@@TOPDIR@@|${topdir}|g" \
        -e "s|@@WORKDIR@@|${build_source_workdir}|g" \
        -e "s|@@LOGDIR@@|${arg_logdir}|g" \
	${topdir}/build-launcher.sh.in > ${topdir}/build-launcher.sh

    chmod +x ${topdir}/build-launcher.sh

    job="${arg_cron} ${topdir}/build-launcher.sh"
    cat <(fgrep -i -v "build-launcher" <(crontab -l)) <(echo "$job") | crontab -
}

#
# Main
#
installPackages

buildSourceDownloadSources
buildSourceBuildSources

ensureUpdateCron
