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

# A build source to build an autotools
# package and install it into "${build_source_prefix}
function buildInstallAutotools() {
    local module=$1
    local changed=$2
    local moduledir="${build_source_workdir}/${module}"

    # No need to re-autogen and build if the gits didnt change
    if [ "${changed}" -eq "0" ]; then
	echo "Module ${module} is up to date, not rebuilding"
	return
    fi

    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${build_source_prefix}/lib/pkgconfig" 

    cd "${moduledir}" || dienow
    echo "Configuring ${module}"
    ./autogen.sh --prefix="${build_source_prefix}" || dienow
    echo "Building ${module}"
    make -j8 || dienow
    echo "Installing ${module}"
    make install || dienow
}
