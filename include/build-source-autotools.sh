# A build source to build an autotools
# packack and install it into $PREFIX
function buildInstallAutotools() {
    local moduledir
    local module

    module=$1
    moduledir="${build_source_workdir}/${module}"
    cd "${moduledir}"

    echo "Configuring ${module}"
    ./autogen.sh --prefix="${PREFIX}"
    echo "Building ${module}"
    make -j8
    echo "Installing ${module}"
    sudo make install
    sudo ldconfig
}
