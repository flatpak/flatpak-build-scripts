# A build source to build a few known
# types of flatpak related repository structures

flatpak_remote_args="--user --no-gpg-verify"
flatpak_install_args="--user --arch=${build_source_arch}"

#
# Ensures a remote exists and points to
# the correct repo
#  $1 The remote name to ensure
#  $2 The repo path
#
function flatpakEnsureRemote() {
    local module=$1
    local repo=$2
    local error_code

    flatpak remote-add ${flatpak_remote_args} ${module} ${repo}
    error_code=$?

    # If it errors, assume it's because it exists
    if [ "${error_code}" -ne "0" ]; then
	flatpak remote-modify ${flatpak_remote_args} ${module} --url ${repo}
	error_code=$?

	# If it exists, just update it's remote uri
	if [ "${error_code}" -ne "0" ]; then

	    # This shouldnt happen
	    dienow "Failed to ensure remote ${module} at repo: ${repo}"
	fi
    fi
}

#
# Installs an asset into the remote for the given module
#  $1 The module
#  $2 The asset to install
#  $3 The version/branch to install
#
function flatpakInstallAsset() {
    local module=$1
    local asset=$2
    local branch=$3
    local error_code

    # Dont specify the branch when it's master
    if [ "${branch}" == "master" ]; then
	branch=
    fi

    # If install reports an error it's probably installed, try an upgrade in that case.
    flatpak install ${flatpak_install_args} ${module} ${asset} ${branch}
    error_code=$?

    if [ "$?" -ne "0" ]; then
	flatpak update ${flatpak_install_args} ${asset} ${branch} || \
	    dienow "Failed to install or update: ${asset}/${branch} from remote ${module}"
    fi
}

#############################################
#          freedesktop-sdk-base             #
#############################################
function buildInstallFlatpakBase() {
    local module=$1
    local assets=(${BASE_SDK_ASSETS["${module}"]})
    local version=${BASE_SDK_VERSION["${module}"]}
    local moduledir="${build_source_workdir}/${module}"

    # Build freedesktop-sdk-base or error out
    echo "Building in ${module}"
    cd "${moduledir}" || dienow
    make ARCH=${build_source_arch} || dienow

    # Ensure there is a remote
    flatpakEnsureRemote "${module}" "file://${moduledir}/repo"

    # Install the assets
    for asset in ${assets[@]}; do
	flatpakInstallAsset "${module}" "${asset}" "${version}"
    done
}

#############################################
#                    SDKS                   #
#############################################
function buildInstallFlatpakSdk() {
    local module=$1
    local assets=(${SDK_ASSETS["${module}"]})
    local version=${SDK_VERSION["${module}"]}
    local moduledir="${build_source_workdir}/${module}"

    # Build the sdk or error out
    echo "Building in ${module}"
    cd "${moduledir}" || dienow
    make ARCH=${build_source_arch} || dienow

    # Ensure there is a remote
    flatpakEnsureRemote "${module}" "file://${moduledir}/repo"

    # Install the assets
    for asset in ${assets[@]}; do
	flatpakInstallAsset "${module}" "${asset}" "${version}"
    done
}

#############################################
#            App json collections           #
#############################################
function buildInstallFlatpakApps() {
    local module=$1
    local moduledir="${build_source_workdir}/${module}"
    local app_id=
    local app_dir="${moduledir}/app"

    cd "${moduledir}" || dienow
    for file in *.json; do
	app_id=$(basename $file .json)

	echo "========== Building $app_id ================"
	rm -rf ${app_dir}
	flatpak-builder --force-clean --ccache --require-changes --repo=repo --arch=${build_source_arch} \
                        --subject="Nightly build of ${APPID}, `date`" \
                        ${app_dir} $file || dienow "Failed to build ${app_id}"
    done
}
