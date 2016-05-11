#!/bin/bash

topdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_source_workdir=${topdir}/work

. ${topdir}/include/build-source.sh
. ${topdir}/include/build-source-autotools.sh

# PREFIX is used by the buildInstallAutotools function
PREFIX=/usr/local

# Make sure we have PKG_CONFIG_PATH set to our prefix during the builds
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${PREFIX}/lib/pkgconfig"
export PKG_CONFIG_PATH

#
# Packages required on Ubuntu 16.04
#
ubuntu_packages=(git build-essential python diffstat gawk chrpath texinfo bison unzip emacs
		 dh-autoreconf gobject-introspection gtk-doc-tools gnome-doc-utils
		 libattr1-dev libcap-dev libglib2.0-dev liblzma-dev e2fslibs-dev
		 libgpg-error-dev libgpgme11-dev libfuse-dev libarchive-dev
		 libgirepository1.0-dev libxau-dev libjson-glib-dev libpolkit-gobject-1-dev
		 libseccomp-dev elfutils libelf-dev libdwarf-dev libsoup2.4-dev)

function installPackages() {
    echo "Ensuring we have the packages we need..."
    sudo apt-get install "${ubuntu_packages[@]}"
}

#
# Sources that we build
#
buildSourceAdd "libgsystem" "git://git.gnome.org/libgsystem"          "master" buildInstallAutotools
buildSourceAdd "ostree"     "git://git.gnome.org/ostree"              "master" buildInstallAutotools
buildSourceAdd "xdg-app"    "https://github.com/gtristan/xdg-app.git" "master" buildInstallAutotools

#
# Main
#
installPackages

buildSourceDownloadSources
buildSourceBuildSources
