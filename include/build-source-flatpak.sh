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
    local extra_targets=${SDK_EXTRA_TARGETS["${module}"]}
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

    if [ "${error_code}" -eq "0" ]; then
        # Ensure there is a remote and install
        flatpakEnsureRemote ${repo_suffix}
        for asset in ${assets[@]}; do
            flatpakInstallAsset "${asset}" "${version}" "${repo_suffix}"
        done

        for extra_target in ${extra_targets[@]}; do
            if [ ! -z "${build_source_logdir}" ]; then
                make "${args[@]}" "${extra_target}" >> "${build_source_logdir}/build-${module}-${build_source_arch}.txt" 2>&1
            else
                make "${args[@]}" "${extra_target}"
            fi
            error_code=$?
            if [ "${error_code}" -ne "0" ]; then break; fi
        done
    fi

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
}

#############################################
#            App json collections           #
#############################################

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
        args+=("--skip-if-unchanged")
    fi

    args+=("--repo=${flatpak_repo}")
    args+=("--arch=${build_source_arch}")
    if [ ! -z "${gpg_arg}" ]; then
	args+=(${gpg_arg})
    fi
    if [ ! -z ${APP_BUILDER_ARGS["${module}"]} ]; then
	args+=(${APP_BUILDER_ARGS["${module}"]})
    fi

    # failing a build here is non-fatal, we want to try to
    # build all the apps even if some fail.
    cd "${moduledir}" || dienow
    for file in *.app; do
	app_id=$(basename $file .app)

	rm -rf ${app_dir}

        # We run the irc notification i parallel, because we want
        # to avoid doing any notitification at all for the
        # continuous case if the json was unchanged
        coproc IRCNOTIFY {
            # Try to read the error code, but time
            # out to check if the app directory
            # exists, which means the build has started
            while ! read -t 1 error_code; do
                if [ -d app ]; then
                    break; # Build started, lets notify on it
                fi
            done

            if [ -d app ]; then
	        notifyIrcTarget ${module} "regular" "build-${module}-${app_id}-${build_source_arch}.txt" "Starting build of '${app_id}'"
            fi

            # Wait until the build is done and we have the error code
            while [ -z "$error_code" ]; do
                read error_code
            done

            if [ -d app ]; then
	        if [ "${error_code}" -ne "0" ]; then
		    notifyIrcTarget ${module} "fail" "build-${module}-${app_id}-${build_source_arch}.txt" "App '${app_id}' build failed"
	        else
		    notifyIrcTarget ${module} "success" "build-${module}-${app_id}-${build_source_arch}.txt"  "App '${app_id}' build success"
	        fi
            elif ${build_source_unconditional}; then
	        notifyIrcTarget ${module} "regular" "build-${module}-${app_id}-${build_source_arch}.txt" "App '${app_id}' already up to date"
            fi
        }

	if [ ! -z "${build_source_logdir}" ]; then
	    ./build.sh $file "${args[@]}" > "${build_source_logdir}/build-${module}-${app_id}-${build_source_arch}.txt" 2>&1
	else
	    ./build.sh $file "${args[@]}"
	fi
	error_code=$?

	# Make an announcement
        echo $error_code >&"${IRCNOTIFY[1]}"
        wait ${IRCNOTIFY_PID}

        # Error code 42 means we skipped the build due to unchanged file
	if [ "${error_code}" -eq "42" ]; then
            echo "No changes to app ${app_id} json, removing log"
            rm "${build_source_logdir}/build-${module}-${app_id}-${build_source_arch}.txt"
        fi

	rm -rf ${app_dir}

	# Failed builds will accumulate quickly in the build directory, zap em
	[ -d "${moduledir}/${flatpak_build_subdir}" ] && rm -rf "${moduledir}/${flatpak_build_subdir}"
    done
}
