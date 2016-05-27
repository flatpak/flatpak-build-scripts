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
    local moduledir="${build_source_workdir}/${module}"

    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${build_source_prefix}/lib/pkgconfig" 

    cd "${moduledir}" || dienow
    echo "Configuring ${module}"
    ./autogen.sh --prefix="${build_source_prefix}" || dienow
    echo "Building ${module}"
    make -j8 || dienow
    echo "Installing ${module}"
    sudo make install || dienow
    sudo ldconfig || dienow
}
