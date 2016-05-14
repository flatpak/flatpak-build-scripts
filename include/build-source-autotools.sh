# A build source to build an autotools
# packack and install it into $PREFIX
function buildInstallAutotools() {
    local moduledir
    local module

    module=$1
    moduledir="${build_source_workdir}/${module}"
    cd "${moduledir}"

    echo "Configuring ${module}"
    PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${build_source_prefix}/lib/pkgconfig" ./autogen.sh --prefix="${build_source_prefix}"
    echo "Building ${module}"
    PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${build_source_prefix}/lib/pkgconfig" make -j8
    echo "Installing ${module}"
    PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${build_source_prefix}/lib/pkgconfig" sudo make install
    sudo ldconfig
}
