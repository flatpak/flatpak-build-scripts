#!/bin/bash
# Copyright (C) 2016 Endless Mobile, Inc.
# Author: Tristan Van Berkom <tristan@codethink.co.uk>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library. If not, see <http://www.gnu.org/licenses/>.

topdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# default options
arg_workdir=${topdir}/work
arg_config=${topdir}/build.conf
arg_schedule=
arg_interval=
arg_headroom_gb=10
arg_refresh_sysdeps=false
arg_refresh_tools=false
arg_setup_apache=false

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
    echo "  -w --workdir  <directory>      The directory to perform builds in (default: 'work' subdirectory)"
    echo "  -c --config   <filename>       Alternative configuration file (default: build.conf in this directory)"
    echo "  -s --schedule <expression>     A cron expression indicating when unconditional builds should run (default: no cron jobs)"
    echo "  -i --interval <minutes>        An interval in minutes indicating how often continuous builds should run (default: none)"
    echo "  -g --headroom <GB>             Gigabytes of headroom required before a build, not counting initial build (default: 10)"
    echo "  --refresh-sysdeps              Install or upgrade required system dependencies using the system package manager (requires sudo)"
    echo "  --refresh-tools                Build or refresh builds of required tooling (flatpak, ostree and libgsystem)"
    echo "  --setup-apache                 Setup the apache server to host the builds and logs (requires sudo)"
    echo
    echo "About unconditional and continuous builds:"
    echo
    echo "  Unconditional builds scheduled with --schedule will attampt to build regardless of whether"
    echo "  or not their manifests have changed in the git repository. This is suitable for nightly builds"
    echo "  because manifests may refer to other external git repositories but running them continuously"
    echo "  can result in the same failure being encountered repeatedly and consequently announced on IRC"
    echo
    echo "  Continuous builds scheduled with --interval will only ever attempt to build if the manifest"
    echo "  has changed in the git repository. This is suitable for continuous building, if a failure can"
    echo "  be fixed with a change to the manifest then the build machine will rebuild on that change"
    echo "  as soon as the interval is up and a build is not currently in progress"
    echo
    echo "About headroom"
    echo "  The --headroom parameter specifies the amount of gigabytes which should be free on disk"
    echo "  before commencing a build. Note that this is not the amount of free space required for"
    echo "  an initial build from scratch, as the base runtime checkout after a build will take"
    echo "  around 30gb which will remain occupied for eternally and remain approximately constant."
    echo
    echo "  Instead, the headroom should signify the amount of free space desired before commencing"
    echo "  any consecutive build, once the entire build has completed at least once."
    echo
    echo "  When launching a build, if less than the desired headroom is available, we will first"
    echo "  prune the ostree repository, leaving only the most recent commit of every branch in place."
    echo "  If this is insufficient, we will purge the build logs."
    echo
}

while : ; do
    case "$1" in
	-h|--help)
	    usage;
	    exit 0;
	    shift ;;

	-w|--workdir)
	    arg_workdir=${2}
	    shift 2 ;;

	-c|--config)
	    arg_config=${2}
	    shift 2 ;;

	-s|--schedule)
	    arg_schedule=${2}
	    shift 2 ;;

	-i|--interval)
	    arg_interval=${2}
	    shift 2 ;;

	-g|--headroom)
	    arg_headroom_gb=${2}
	    shift 2 ;;

	--refresh-sysdeps)
	    arg_refresh_sysdeps=true
	    shift ;;

	--refresh-tools)
	    arg_refresh_tools=true
	    shift ;;

	--setup-apache)
	    arg_setup_apache=true
	    shift ;;

	*)
	    break ;;
    esac
done

#
# Some sanity checks and path resolutions
#
tooldir=${topdir}/tools-build
prefix=${topdir}/tools-inst

mkdir -p "${tooldir}" || dienow "Failed to create tools build directory: ${tooldir}"
mkdir -p "${prefix}" || dienow "Failed to create tools install directory: ${prefix}"
mkdir -p "${arg_workdir}" || dienow "Failed to create work directory: ${arg_workdir}"
mkdir -p "${arg_workdir}/export"
mkdir -p "${arg_workdir}/build"

tooldir="$(cd ${tooldir} && pwd)"
prefix="$(cd ${prefix} && pwd)"
arg_workdir="$(cd ${arg_workdir} && pwd)"

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
build_source_workdir=${tooldir}
build_source_build="${arg_workdir}/build"
build_source_prefix=${prefix}

# Import the build source mechanics, the flatpak sources and the build config
. ${topdir}/include/build-source.sh
. ${topdir}/include/build-source-autotools.sh

function refreshTools() {
    #
    # Refresh the build tooling itself with the autotools stuff
    #
    buildSourceAdd "ostree"     "https://github.com/ostreedev/ostree"    "v2018.8" buildInstallAutotools
    buildSourceAdd "flatpak"    "https://github.com/flatpak/flatpak.git" "1.0.1" buildInstallAutotools
    buildSourceAdd "flatpak-builder"    "https://github.com/flatpak/flatpak-builder.git" "1.0.0" buildInstallAutotools

    buildSourceRun
}

function refreshSysdeps() {
    local os_id=$(source /etc/os-release; echo $ID)

    #
    # Packages required on Ubuntu 16.04
    #
    ubuntu_packages=(git build-essential python diffstat gawk chrpath texinfo bison unzip
		     dh-autoreconf gobject-introspection gtk-doc-tools gnome-doc-utils
		     libattr1-dev libcap-dev libglib2.0-dev liblzma-dev e2fslibs-dev
		     libgpg-error-dev libgpgme11-dev libfuse-dev libarchive-dev
		     libgirepository1.0-dev libxau-dev libjson-glib-dev libpolkit-gobject-1-dev
		     libseccomp-dev elfutils libelf-dev libdwarf-dev libsoup2.4-dev
		     libappstream-glib-dev libcurl4-openssl-dev fuse)
    #
    # Packages required on RHEL
    #
    rhel_packages=(libarchive-devel, gpgme-devel, fuse-devel bison polkit-devel libseccomp-devel
		   elfutils elfutils-devel wget  git bzr libsoup-devel json-glib-devel glibc-devel gcc
		   autoconf libtool gobject-introspection-devel libXau-devel intltool gtk-doc
		   libattr-devel e2fsprogs-devel libseccomp-devel gcc-c++ diffstat texinfo chrpath unzip)

    # IRC support
    ubuntu_packages+=(python-twisted)
    rhel_packages+=(python-twisted-core)

    # Apache support
    ubuntu_packages+=(apache2)
    rhel_packages+=(httpd)

    echo "Ensuring we have the packages we need..."
    if [ "x$os_id" = "xubuntu" ] ; then
	sudo apt-get install "${ubuntu_packages[@]}"
    elif [ "x$os_id" = "xrhel" ] ; then
	sudo yum install "${rhel_packages[@]}"
    else
	echo "Unsupported distribution"
	exit 1
    fi
}

# Ensure the build schedule for either unconditional
# or continuous builds.
#
#  $1 - "continuous" or "unconditional"
#
function ensureBuildSchedule () {
    local schedule_type=$1
    local job=
    local script_name=

    # Create the launch script based on our current configuration
    # and ensure that there is an entry in the user's crontab for
    # the launcher.
    #
    sed -e "s|@@TOPDIR@@|${topdir}|g" \
        -e "s|@@PREFIX@@|${build_source_prefix}|g" \
        -e "s|@@CONFIG@@|${arg_config}|g" \
        -e "s|@@WORKDIR@@|${arg_workdir}|g" \
	-e "s|@@HEADROOMGB@@|${arg_headroom_gb}|g" \
	${topdir}/data/build-launcher.sh.in > ${topdir}/launcher.tmp.sh

    if [ "${schedule_type}" == "continuous" ]; then
	script_name="build-continuous.sh"
	job="*/${arg_interval} * * * * ${topdir}/${script_name}"

	sed -e "s|@@UNCONDITIONAL@@||g" \
	    -e "s|@@FLOCKNOBLOCK@@|-n|g" \
	    ${topdir}/launcher.tmp.sh > ${topdir}/${script_name}
    else
	script_name="build-launcher.sh"
	job="${arg_schedule} ${topdir}/${script_name}"

	sed -e "s|@@UNCONDITIONAL@@|--unconditional|g" \
	    -e "s|@@FLOCKNOBLOCK@@||g" \
	    ${topdir}/launcher.tmp.sh > ${topdir}/${script_name}
    fi

    rm -f ${topdir}/launcher.tmp.sh
    chmod +x ${topdir}/${script_name}

    # Register the job with user's crontab
    cat <(fgrep -i -v "${script_name}" <(crontab -l)) <(echo "$job") | crontab -
}

function configureApache () {
    apache_data="${topdir}/data/apache"
    apache_dir="/etc/apache2"
    apache_conf="${apache_dir}/apache2.conf"
    apache_site="${apache_dir}/sites-available/000-default.conf"
    apache_ssl="${apache_dir}/sites-available/default-ssl.conf"
    export_dir="${arg_workdir}/export"

    if [ ! -f "${apache_conf}" ] || [ ! -f "${apache_conf}" ] || [ ! -f "${apache_ssl}" ]; then
	echo "Unrecognized apache server; not setting up apache"
	return
    fi

    # Configure apache to serve our build results
    #
    sed -e "s|@@SITE_ROOT@@|${export_dir}|g" ${apache_data}/apache2.conf.in     | sudo tee ${apache_conf} > /dev/null
    sed -e "s|@@SITE_ROOT@@|${export_dir}|g" ${apache_data}/000-default.conf.in | sudo tee ${apache_site} > /dev/null
    sed -e "s|@@SITE_ROOT@@|${export_dir}|g" ${apache_data}/default-ssl.conf.in | sudo tee ${apache_ssl}  > /dev/null

    # Restart with new config
    #
    echo "Restarting apache server to serve build results at: ${export_dir}"
    sudo service apache2 restart
}

#
# Main
#
if ! $arg_refresh_sysdeps && ! $arg_refresh_tools && ! $arg_setup_apache &&
	[ -z "${arg_schedule}" ] && [ -z "${arg_interval}" ]; then

    echo "No arguments with any consequences specified, run this script with --help to explain possible arguments"
    exit 1
fi

# Install or upgrade system dependencies with package manager
if $arg_refresh_sysdeps; then
    refreshSysdeps
fi

# Refresh build tooling if asked to
if $arg_refresh_tools; then
    refreshTools
fi

# Schedule or change schedule of the nightlies 
if [ ! -z "${arg_schedule}" ]; then
    ensureBuildSchedule "unconditional"
fi

# Schedule or change interval of the continuous builds
if [ ! -z "${arg_interval}" ]; then
    ensureBuildSchedule "continuous"
fi

# Automatically squash the system apache configuration
# to serve the export directory
if $arg_setup_apache; then
    configureApache
fi
