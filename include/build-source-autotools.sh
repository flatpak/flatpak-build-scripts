
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
