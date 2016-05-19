# A build source to build a few known
# types of flatpak related repository structures

flatpak_repo="${build_source_workdir}/export/repo"
flatpak_remote_args="--user --no-gpg-verify"
flatpak_install_args="--user --arch=${build_source_arch}"
flatpak_builder_args="--force-clean --ccache --require-changes --repo=${flatpak_repo} --arch=${build_source_arch}"

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

    if [ "${error_code}" -ne "0" ]; then
	flatpak update ${flatpak_install_args} ${asset} ${branch} || \
	    dienow "Failed to install or update: ${asset}/${branch} from remote ${module}"
    fi
}

function flatpakAnnounceBuild() {
    local module=$1

    echo "Commencing build of ${module}"
    if [ ! -z "${build_source_logdir}" ]; then
	echo "Logging build in build-${module}.log"
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
    flatpakAnnounceBuild "${module}"

    cd "${moduledir}" || dienow
    if [ ! -z "${build_source_logdir}" ]; then
	make ARCH=${build_source_arch} REPO=${flatpak_repo} > "${build_source_logdir}/build-${module}.log" 2>&1 || dienow
    else
	make ARCH=${build_source_arch} REPO=${flatpak_repo} || dienow
    fi

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
    flatpakAnnounceBuild "${module}"

    cd "${moduledir}" || dienow
    if [ ! -z "${build_source_logdir}" ]; then
	make ARCH=${build_source_arch} REPO=${flatpak_repo} > "${build_source_logdir}/build-${module}.log" 2>&1 || dienow
    else
	make ARCH=${build_source_arch} REPO=${flatpak_repo} || dienow
    fi

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
    local error_code

    # failing a build here is non-fatal, we want to try to
    # build all the apps even if some fail.
    cd "${moduledir}" || dienow
    for file in *.json; do
	app_id=$(basename $file .json)

	flatpakAnnounceBuild "${app_id}"

	rm -rf ${app_dir}
	if [ ! -z "${build_source_logdir}" ]; then
	    flatpak-builder ${flatpak_builder_args} --subject="Nightly build of ${app_id}, `date`" \
                            ${app_dir} $file > "${build_source_logdir}/build-${app_id}.log" 2>&1
	else
	    flatpak-builder ${flatpak_builder_args} --subject="Nightly build of ${app_id}, `date`" \
                            ${app_dir} $file
	fi

	error_code=$?
	if [ "${error_code}" -ne "0" ]; then
	    echo "Failed to build ${app_id}"
	fi

	rm -rf ${app_dir}
    done
}
