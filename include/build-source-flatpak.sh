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

# A build source to build a few known
# types of flatpak related repository structures

flatpak_remote="builds"
flatpak_repo="${build_source_workdir}/export/repo"
flatpak_remote_args="--user --no-gpg-verify"
flatpak_install_args="--user --arch=${build_source_arch}"
flatpak_subdir=".flatpak-builder"
flatpak_build_subdir="${flatpak_subdir}/build"

#
# Ensures a remote exists and points to
# the common repo
#
function flatpakEnsureRemote() {
    local error_code
    local repo_url="file://${flatpak_repo}"

    echo "Ensuring the global remote exists and points to: ${repo_url}"
    flatpak remote-add ${flatpak_remote_args} ${flatpak_remote} ${repo_url} > /dev/null 2>&1
    error_code=$?

    # If it errors, assume it's because it exists
    if [ "${error_code}" -ne "0" ]; then
	flatpak remote-modify ${flatpak_remote_args} ${flatpak_remote} --url ${repo_url} > /dev/null 2>&1
	error_code=$?

	# If it exists, just update it's remote uri
	if [ "${error_code}" -ne "0" ]; then

	    # This shouldnt happen
	    dienow "Failed to ensure our global remote at: ${repo_url}"
	fi
    fi
}

#
# Installs an asset into the remote
#  $1 The asset to install
#  $2 The version/branch to install
#
function flatpakInstallAsset() {
    local asset=$1
    local branch=$2
    local error_code

    echo "Installing asset ${asset} at branch ${branch}"

    # Dont specify the branch when it's master
    if [ "${branch}" == "master" ]; then
	branch=
    fi

    # If install reports an error it's probably installed, try an upgrade in that case.
    flatpak install ${flatpak_install_args} ${flatpak_remote} ${asset} ${branch} > /dev/null 2>&1
    error_code=$?

    if [ "${error_code}" -ne "0" ]; then
	flatpak update ${flatpak_install_args} ${asset} ${branch} || \
	    dienow "Failed to install or update: ${asset}/${branch} from remote ${flatpak_remote}"
    fi
}

function flatpakAnnounceBuild() {
    local module=$1

    echo "Commencing build of ${module}"
    if [ ! -z "${build_source_logdir}" ]; then
	echo "Logging build in build-${module}.txt"
    fi
}

#############################################
#          freedesktop-sdk-base             #
#############################################
function buildInstallFlatpakBase() {
    local module=$1
    local changed=$2
    local assets=(${BASE_SDK_ASSETS["${module}"]})
    local version=${BASE_SDK_VERSION["${module}"]}
    local branch=${build_source_branches["${module}"]}
    local moduledir="${build_source_workdir}/${module}"
    local error_code
    args=()

    # No need to build the base runtime if the gits didnt change
    if [ "${changed}" -eq "0" ]; then
	echo "Module ${module} is up to date, not rebuilding"
	return
    fi

    flatpakAnnounceBuild "${module}"
    cd "${moduledir}" || dienow

    args+=("ARCH=${build_source_arch}")
    args+=("REPO=${flatpak_repo}")
    if [ ! -z "${flatpak_gpg_key}" ]; then
	args+=("GPG_ARGS=--gpg-sign=${flatpak_gpg_key}")
    fi

    if [ ! -z "${build_source_logdir}" ]; then
	make "${args[@]}" > "${build_source_logdir}/build-${module}.txt" 2>&1
    else
	make "${args[@]}"
    fi
    error_code=$?

    # Make an announcement
    if [ "${error_code}" -ne "0" ]; then
	notifyIrcTarget ${module} "fail" "build-${module}.txt" \
			"Runtime ${module} (${branch}) failed"
    else
	notifyIrcTarget ${module} "success" "build-${module}.txt" \
			"Runtime ${module} (${branch}) success"
    fi

    # A runtime build failure is fatal, we can't build anything else without it
    [ "${error_code}" -ne "0" ] && dienow

    # Ensure there is a remote and install
    flatpakEnsureRemote
    for asset in ${assets[@]}; do
	flatpakInstallAsset "${asset}" "${version}"
    done
}

#############################################
#                    SDKS                   #
#############################################
function buildInstallFlatpakSdk() {
    local module=$1
    local changed=$2
    local assets=(${SDK_ASSETS["${module}"]})
    local version=${SDK_VERSION["${module}"]}
    local branch=${build_source_branches["${module}"]}
    local moduledir="${build_source_workdir}/${module}"
    local error_code
    args=()

    # Bail out if we asked for a conditional build and nothing changed
    if ! ${build_source_unconditional}; then
	if [ "${changed}" -eq "0" ]; then
	    echo "Module ${module} is up to date, not rebuilding"
	    return
	fi
    fi

    flatpakAnnounceBuild "${module}"
    cd "${moduledir}" || dienow

    args+=("ARCH=${build_source_arch}")
    args+=("REPO=${flatpak_repo}")
    if [ ! -z "${flatpak_gpg_key}" ]; then
	args+=("EXPORT_ARGS=--gpg-sign=${flatpak_gpg_key}")
    fi

    if [ ! -z "${build_source_logdir}" ]; then
	make "${args[@]}" > "${build_source_logdir}/build-${module}.txt" 2>&1
    else
	make "${args[@]}"
    fi
    error_code=$?

    # Make an announcement if something was built
    if [ -d "${moduledir}/sdk" ]; then
	if [ "${error_code}" -ne "0" ]; then
	    notifyIrcTarget ${module} "fail" "build-${module}.txt" \
			    "SDK ${module} (${branch}) failed"
	else
	    notifyIrcTarget ${module} "success" "build-${module}.txt" \
			    "SDK ${module} (${branch}) success"
	fi

	rm -rf "${moduledir}/sdk"
    fi

    # Failed builds will accumulate quickly in the build directory, zap em
    [ -d "${moduledir}/${flatpak_build_subdir}" ] && rm -rf "${moduledir}/${flatpak_build_subdir}"

    # An SDK build failure is fatal, we can't build the apps without knowing we have the SDK
    [ "${error_code}" -ne "0" ] && dienow

    # Ensure there is a remote and install
    flatpakEnsureRemote
    for asset in ${assets[@]}; do
	flatpakInstallAsset "${asset}" "${version}"
    done
}

#############################################
#            App json collections           #
#############################################
function buildInstallFlatpakApps() {
    local module=$1
    local changed=$2
    local branch=${build_source_branches["${module}"]}
    local moduledir="${build_source_workdir}/${module}"
    local app_id=
    local app_dir="${moduledir}/app"
    local error_code
    args=()

    # Bail out if we asked for a conditional build and nothing changed
    if ! ${build_source_unconditional}; then
	if [ "${changed}" -eq "0" ]; then
	    echo "Module ${module} is up to date, not rebuilding"
	    return
	fi
    fi

    args+=("--force-clean")
    args+=("--ccache")
    args+=("--require-changes")
    args+=("--repo=${flatpak_repo}")
    args+=("--arch=${build_source_arch}")
    if [ ! -z "${flatpak_gpg_key}" ]; then
	args+=("--gpg-sign=${flatpak_gpg_key}")
    fi

    # failing a build here is non-fatal, we want to try to
    # build all the apps even if some fail.
    cd "${moduledir}" || dienow
    for file in *.json; do
	app_id=$(basename $file .json)

	flatpakAnnounceBuild "${app_id}"

	rm -rf ${app_dir}
	if [ ! -z "${build_source_logdir}" ]; then
	    flatpak-builder "${args[@]}" --subject="Nightly build of ${app_id}, `date`" \
                            ${app_dir} $file > "${build_source_logdir}/build-${app_id}.txt" 2>&1
	else
	    flatpak-builder "${args[@]}" --subject="Nightly build of ${app_id}, `date`" \
                            ${app_dir} $file
	fi
	error_code=$?

	# Make an announcement if something was built
	if [ -d "${app_dir}" ]; then
	    if [ "${error_code}" -ne "0" ]; then
		notifyIrcTarget ${module} "fail" "build-${app_id}.txt" \
				"App ${module} (${branch}) '${app_id}' failed"
	    else
		notifyIrcTarget ${module} "success" "build-${app_id}.txt" \
				"App ${module} (${branch}) '${app_id}' success"
	    fi
	    rm -rf ${app_dir}
	fi

	# Failed builds will accumulate quickly in the build directory, zap em
	[ -d "${moduledir}/${flatpak_build_subdir}" ] && rm -rf "${moduledir}/${flatpak_build_subdir}"
    done
}
