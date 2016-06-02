#!/bin/bash
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


# An ordered table of sources with abstract
# build functions.
#
build_source_modules=()
declare -A build_source_repos
declare -A build_source_branches
declare -A build_source_funcs
declare -A build_source_irc_targets

#
# The current module
#
build_source_current=

#
# Called in build source functions when the build fails
#
function dienow() {
    local errmsg=$1

    if [ ! -z "${build_source_current}" ]; then
	echo -n "Build of ${build_source_current} failed" 1>&2
    else
	echo -n "Build failed" 1>&2
    fi

    if [ ! -z "$errmsg" ]; then
	echo ": $1" 1>&2
    else
	echo 1>&2
    fi

    exit 1
}

#
# Add a source to the array
#  $1 module name to add
#  $2 git repository url
#  $3 the branch name of the git module
#  $4 function to build with, like buildInstallAutotools()
#  $5 IRC target id
#
function buildSourceAdd() {
    local module=$1
    local repo=$2
    local branch=$3
    local build_func=$4
    local irc_target=$5

    build_source_modules+=("${module}")
    build_source_repos["${module}"]="$repo"
    build_source_branches["${module}"]="$branch"
    build_source_funcs["${module}"]=${build_func}
    build_source_irc_targets["${module}"]="${irc_target}"
}

function buildSourceCheckout() {
    local module=$1
    local branch=${build_source_branches["${module}"]}
    local repo=${build_source_repos["${module}"]}

    echo "Checking out ${module} from ${repo}"
    mkdir -p ${build_source_workdir} && cd "${build_source_workdir}" || dienow

    git clone ${repo} ${module} || dienow
    cd "${module}" || dienow
    git checkout ${branch} || dienow

    # Make sure we got the submodules
    git submodule init
    git submodule update
}

function buildSourceUpdate() {
    local module=$1
    local branch=${build_source_branches["${module}"]}
    local repo=${build_source_repos["${module}"]}
    local moduledir="${build_source_workdir}/${module}"
    local error_code

    echo "Fetching from ${repo}"
    cd "${moduledir}" || dienow

    # fetch will not fail in any recoverable way
    git fetch || dienow "Failed to fetch from '${repo}'"

    # deactivate submodules during the update
    git submodule deinit --force .
    error_code=$?

    # if we deactivated any submodules, then we have submodules
    if [ "${error_code}" -eq "0" ]; then

	# When a git module changes origin, it needs
	# a new checkout, only with --force
	if $build_source_force; then
	    rm -rf "${moduledir}/.git/modules/*"
	fi
    fi

    # ensure we're on the right branch
    git checkout ${branch}
    error_code=$?
    if [ "${error_code}" -ne "0" ]; then
	if $build_source_force; then
	    git clean -xdf || dienow "Unable to cleanup repository"
	    git reset --hard ${branch} || dienow "Unable to hard reset repository"
	else
	    dienow "Unable to checkout branch: ${branch} (try --force)"
	fi
    fi

    # get changes
    git pull --ff-only origin ${branch}
    error_code=$?
    if [ "${error_code}" -ne "0" ]; then
	if $build_source_force; then

	    # Just nuke it and re-checkout
	    rm -rf ${moduledir}
	    buildSourceCheckout ${module}
	    return
	else
	    dienow "Failed to pull from origin branch: ${branch} (try --force)"
	fi
    fi

    # Make sure we got the submodules
    git submodule init
    git submodule update
}

function buildSourceDownload() {
    local module=$1

    build_source_current=${module}

    if [ -d "${build_source_workdir}/${module}" ]; then
	buildSourceUpdate ${module}
    else
	buildSourceCheckout ${module}
    fi

    build_source_current=
}

#
# Build a source by name, calling it's build_func
#  $1 module name to build
#
function buildSourceBuild() {
    local module=$1

    build_source_current=${module}
    ${build_source_funcs["${module}"]} "${module}"
    build_source_current=
}

#
# Run the build
#
function buildSourceRun() {
    local module

    if [ ! -z "${build_source_target}" ]; then
	buildSourceDownload "${build_source_target}"
	buildSourceBuild "${build_source_target}"
    else
	for module in "${build_source_modules[@]}"; do
	    buildSourceDownload "${module}"
	    buildSourceBuild "${module}"
	done
    fi
}

#
# Make an IRC announcement for the given module
#  $1 module name, as listed in build.conf
#  $2 message type, can be one of: regular,success,fail
#  $3 build log short name (without ${build_source_logdir})
#  $4 message to send
#
# The announcement will be made with the following format:
#
#   [ ${BUILD_ARCH} - ${BUILD_LABEL} ] <message>: Log file location
#
function notifyIrcTarget() {
    local module=$1
    local message_type=$2
    local short_log=$3
    local message=$4
    local irc_target=${build_source_irc_targets["${module}"]}

    # Just early return if this module is not configured for IRC notifications
    if [ -z "${irc_target}" ]; then
	return
    fi

    local irc_server=${IRC_TARGET_SERVER["${irc_target}"]}
    local irc_port=${IRC_TARGET_PORT["${irc_target}"]}
    local irc_channel=${IRC_TARGET_CHANNEL["${irc_target}"]}
    local irc_nick=${IRC_TARGET_NICK["${irc_target}"]}
    local irc_join=${IRC_TARGET_JOIN["${irc_target}"]}
    local full_log=${BUILD_URL}/${build_source_logdir#${build_source_export}}/${short_log}
    local full_message="[ ${BUILD_ARCH} ] ${message}: ${full_log}"

    local args="-s ${irc_server} -p ${irc_port} -c ${irc_channel} -n ${irc_nick} -t ${message_type}"
    if [ "${irc_join}" != "yes" ]; then
	args=${args}" --nojoin"
    fi

    # We block annoyingly because we can launch many of them at the same time otherwise,
    # also we redirect to /dev/null just incase one day there is sensitive irc login information
    # that would otherwise end up in the master build.log
    #
    ${topdir}/extra/irc-notify.py ${args[@]} "${full_message}" > /dev/null 2>&1
}
