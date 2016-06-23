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

flatpak_remote_args="--user --no-gpg-verify"
flatpak_install_args="--user"
flatpak_subdir=".flatpak-builder"
flatpak_build_subdir="${flatpak_subdir}/build"

#
# Ensures a remote exists and points to
# the common repo
#
function flatpakEnsureRemote() {
    local repo_suffix=$1
    local flatpak_repo="${build_source_workdir}/export/repo${repo_suffix}"
    local flatpak_remote="builds${repo_suffix}"

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
    local repo_suffix=$3
    local flatpak_remote="builds${repo_suffix}"
    local error_code

    echo "Installing asset ${asset} at branch ${branch} to repo${repo_suffix}"

    # Dont specify the branch when it's master
    if [ "${branch}" == "master" ]; then
	branch=
    fi

    local arch_arg="--arch=${build_source_arch}"

    # If install reports an error it's probably installed, try an upgrade in that case.
    flatpak install ${flatpak_install_args} ${arch_arg} ${flatpak_remote} ${asset} ${branch} > /dev/null 2>&1
    error_code=$?

    if [ "${error_code}" -ne "0" ]; then
	flatpak update ${flatpak_install_args} ${arch_arg} ${asset} ${branch} || \
	    dienow "Failed to install or update: ${asset}/${branch} from remote ${flatpak_remote}"
    fi
}

function composeGpgArgs() {
    if [ ! -z "${BUILD_GPG_KEY}" ]; then
	if [ ! -z "${BUILD_GPG_HOMEDIR}" ]; then
	    echo "--gpg-sign=${BUILD_GPG_KEY} --gpg-homedir=${BUILD_GPG_HOMEDIR}"
	else
	    echo "--gpg-sign=${BUILD_GPG_KEY}"
	fi
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
    local repo_suffix=${BASE_SDK_REPO_SUFFIX["${module}"]}
    local flatpak_repo="${build_source_workdir}/export/repo${repo_suffix}"
    local flatpak_remote="builds${repo_suffix}"
    local branch=${build_source_branches["${module}"]}
    local archdir="${build_source_build}/${build_source_arch}"
    local moduledir="${archdir}/${module}"
    local gpg_arg=$(composeGpgArgs)
    local error_code
    args=()

    # No need to build the base runtime if the gits didnt change
    if [ "${changed}" -eq "0" ]; then
	echo "Module ${module} is up to date, not rebuilding"
	return
    fi

    notifyIrcTarget ${module} "regular" "build-${module}-${build_source_arch}.txt" "Starting runtime build"
    cd "${moduledir}" || dienow

    args+=("ARCH=${build_source_arch}")
    args+=("REPO=${flatpak_repo}")
    if [ ! -z "${gpg_arg}" ]; then
	args+=("GPG_ARGS=${gpg_arg}")
    fi

    if [ ! -z "${build_source_logdir}" ]; then
	make "${args[@]}" > "${build_source_logdir}/build-${module}-${build_source_arch}.txt" 2>&1
    else
	make "${args[@]}"
    fi
    error_code=$?

    # Make an announcement
    if [ "${error_code}" -ne "0" ]; then
	notifyIrcTarget ${module} "fail" "build-${module}-${build_source_arch}.txt" "Runtime build failed"
    else
	notifyIrcTarget ${module} "success" "build-${module}-${build_source_arch}.txt" "Runtime build success"
    fi

    # A runtime build failure is fatal, we can't build anything else without it
    [ "${error_code}" -ne "0" ] && dienow

    # Ensure there is a remote and install
    flatpakEnsureRemote ${repo_suffix}
    for asset in ${assets[@]}; do
	flatpakInstallAsset "${asset}" "${version}" "${repo_suffix}"
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
    local repo_suffix=${SDK_REPO_SUFFIX["${module}"]}
    local flatpak_repo="${build_source_workdir}/export/repo${repo_suffix}"
    local flatpak_remote="builds${repo_suffix}"
    local branch=${build_source_branches["${module}"]}
    local archdir="${build_source_build}/${build_source_arch}"
    local moduledir="${archdir}/${module}"
    local gpg_arg=$(composeGpgArgs)
    local error_code
    args=()

    # Bail out if we asked for a conditional build and nothing changed
    if ! ${build_source_unconditional}; then
	if [ "${changed}" -eq "0" ]; then
	    echo "Module ${module} is up to date, not rebuilding"
	    return
	fi
    fi

    notifyIrcTarget ${module} "regular" "build-${module}-${build_source_arch}.txt" "Starting SDK build"
    cd "${moduledir}" || dienow

    args+=("ARCH=${build_source_arch}")
    args+=("REPO=${flatpak_repo}")
    if [ ! -z "${gpg_arg}" ]; then
	args+=("EXPORT_ARGS=${gpg_arg}")
    fi

    if [ ! -z "${build_source_logdir}" ]; then
	make "${args[@]}" > "${build_source_logdir}/build-${module}-${build_source_arch}.txt" 2>&1
    else
	make "${args[@]}"
    fi
    error_code=$?

    # Make an announcement if something was built
    if [ -d "${moduledir}/sdk" ]; then
	if [ "${error_code}" -ne "0" ]; then
	    notifyIrcTarget ${module} "fail" "build-${module}-${build_source_arch}.txt" "SDK build failed"
	else
	    notifyIrcTarget ${module} "success" "build-${module}-${build_source_arch}.txt" "SDK build success"
	fi

	rm -rf "${moduledir}/sdk"
    else
	notifyIrcTarget ${module} "regular" "build-${module}-${build_source_arch}.txt" "SDK already up to date"
    fi

    # Failed builds will accumulate quickly in the build directory, zap em
    [ -d "${moduledir}/${flatpak_build_subdir}" ] && rm -rf "${moduledir}/${flatpak_build_subdir}"

    # An SDK build failure is fatal, we can't build the apps without knowing we have the SDK
    [ "${error_code}" -ne "0" ] && dienow

    # Ensure there is a remote and install
    flatpakEnsureRemote ${repo_suffix}
    for asset in ${assets[@]}; do
	flatpakInstallAsset "${asset}" "${version}" "${repo_suffix}"
    done
}

#############################################
#            App json collections           #
#############################################

# Reports whether a json file has changed in an App
# repository full of build manifests, this keeps a copy
# of the last run.
#
# Reports exit status 0 (bash true) if the app manifest is unchanged
# and 1 (bash false) if the module was freshly checked out or if the
# app manifest is new or changed.
function checkAppUnchanged() {
    local module=$1
    local app_id=$2
    local archdir="${build_source_build}/${build_source_arch}"
    local moduledir="${archdir}/${module}"
    local cachedir="${archdir}/${module}-cache"
    local changed=0

    if [ ! -d "${cachedir}" ] || [ ! -f "${cachedir}/${app_id}.json" ]; then
	mkdir -p "${cachedir}"
	changed=1
    elif ! diff "${moduledir}/${app_id}.json" "${cachedir}/${app_id}.json" > /dev/null; then
	changed=1
    fi

    cp -f "${moduledir}/${app_id}.json" "${cachedir}/${app_id}.json"

    return ${changed}
}

function buildInstallFlatpakApps() {
    local module=$1
    local changed=$2
    local branch=${build_source_branches["${module}"]}
    local archdir="${build_source_build}/${build_source_arch}"
    local repo_suffix=${APP_REPO_SUFFIX["${module}"]}
    local flatpak_repo="${build_source_workdir}/export/repo${repo_suffix}"
    local flatpak_remote="builds${repo_suffix}"
    local moduledir="${archdir}/${module}"
    local app_id=
    local app_dir="${moduledir}/app"
    local gpg_arg=$(composeGpgArgs)
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
    if [ ! -z "${gpg_arg}" ]; then
	args+=(${gpg_arg})
    fi

    # failing a build here is non-fatal, we want to try to
    # build all the apps even if some fail.
    cd "${moduledir}" || dienow
    for file in *.json; do
	app_id=$(basename $file .json)

	# Check (and track) whether this app's manifest has changed
	if checkAppUnchanged "${module}" "${app_id}"; then

	    # Skip the module if we asked for a conditional build
	    # and this app's manifest is unchanged.
	    if ! ${build_source_unconditional}; then
		continue
	    fi
	fi

	notifyIrcTarget ${module} "regular" "build-${app_id}-${build_source_arch}.txt" "Starting build of '${app_id}'"

	rm -rf ${app_dir}
	if [ ! -z "${build_source_logdir}" ]; then
	    flatpak-builder "${args[@]}" --subject="Nightly build of ${app_id}, `date`" \
                            ${app_dir} $file > "${build_source_logdir}/build-${app_id}-${build_source_arch}.txt" 2>&1
	else
	    flatpak-builder "${args[@]}" --subject="Nightly build of ${app_id}, `date`" \
                            ${app_dir} $file
	fi
	error_code=$?

	# Make an announcement
	if [ -d "${app_dir}" ]; then
	    if [ "${error_code}" -ne "0" ]; then
		notifyIrcTarget ${module} "fail" "build-${app_id}-${build_source_arch}.txt" "App '${app_id}' build failed"
	    else
		notifyIrcTarget ${module} "success" "build-${app_id}-${build_source_arch}.txt"  "App '${app_id}' build success"
	    fi
	    rm -rf ${app_dir}
	else
	    notifyIrcTarget ${module} "regular" "build-${app_id}-${build_source_arch}.txt" "App '${app_id}' already up to date"
	fi

	# Failed builds will accumulate quickly in the build directory, zap em
	[ -d "${moduledir}/${flatpak_build_subdir}" ] && rm -rf "${moduledir}/${flatpak_build_subdir}"
    done
}
