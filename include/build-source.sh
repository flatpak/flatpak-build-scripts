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

# Checks whether the given word is found
# in the given word list
#
#  $1 - The word to check for
#  $2 - The word list
#
# Returns 0 (true in bash) if the word was
# found, otherwise 1 (false) if the word was
# not found.
function wordInList() {
    local word=$1
    local list=($2)

    for iter in ${list[@]}; do

	if [ "${iter}" == "${word}" ]; then
	    return 0
	fi
    done

    return 1;
}

# Checks if the amount of headroom required is
# available on the filesystem where we perform builds
#
#  $1 - Amount of desired GB of free space before a build
#
# Returns 0 (bash true) if the required space is available,
# otherwise returns 1 (bash false)
#
function headroomAvailable() {
    local headroom_gb=$1
    local available_bytes=0
    local available_gb=0

    # Get the amount of free blocks * block size (bytes) available
    # to a regular user on the filesystem where builds occur.
    available_bytes=$(($(stat -f --format="%a*%S" ${build_source_workdir})))

    # Devide down to gigabytes
    available_gb=$((${available_bytes} / 1024 / 1024 / 1024))

    if [ $available_gb -lt $headroom_gb ]; then
	return 1
    fi

    return 0
}

function cullOstreeRepo() {
    for ostree_repo in ${build_source_workdir}/export/repo*; do
        if [ -d "${ostree_repo}" ]; then
	    # Removes all but the latest commits of every existing branch
	    # in the exported ostree repository (I.e. only keep the latest
	    # build of everything)
	    ostree prune --repo=${ostree_repo} --depth=0 --refs-only
        fi
    done
}

function purgeLogs() {
    local logdir="${build_source_workdir}/export/logs"

    rm -rf "${logdir}"
}

# Attempt to free space and ensure there
# is enough space to perform the build.
#
#  $1 - Amount of desired GB of free space before a build
#
function ensureHeadroomGigabytes() {
    local headroom_gb=$1

    if ! headroomAvailable ${headroom_gb}; then

	# First cull the ostree repository
	echo "Culling ostree repo for more space"
	cullOstreeRepo

	if ! headroomAvailable ${headroom_gb}; then

	    # If culling the ostree repo was not enough, go ahead
	    # and purge the logs as well
	    echo "Purging logs for more space"
	    purgeLogs

	    if ! headroomAvailable ${headroom_gb}; then
		# Build server in need of maintenance, todo: Notify some global IRC target
		#
		dienow "Build server in need of maintenance, less than ${headroom_gb} GB of free space available before building"
	    fi
	fi
    fi
}

#
# Add a source to the array
#  $1 module name to add
#  $2 git repository url
#  $3 the branch name of the git module
#  $4 function to build with, like buildInstallAutotools()
#  $5 IRC target id wordlist
#
function buildSourceAdd() {
    local module=$1
    local repo=$2
    local branch=$3
    local build_func=$4
    local irc_targets=$5

    build_source_modules+=("${module}")
    build_source_repos["${module}"]="$repo"
    build_source_branches["${module}"]="$branch"
    build_source_funcs["${module}"]=${build_func}
    build_source_irc_targets["${module}"]="${irc_targets}"
}

# Reports whether the tip git commit ID has changed
# after a checkout or update, stores the latest commit ID
# in a file
function buildSourceTrackChanges() {
    local module=$1
    local branch=${build_source_branches["${module}"]}
    local archdir="${build_source_build}/${build_source_arch}"
    local moduledir="${archdir}/${module}"
    local changed=0

    cd "${moduledir}" || dienow

    if [ ! -f "${archdir}/${module}.latest" ]; then
	git rev-parse "${branch}" > "${archdir}/${module}.latest"
	changed=1
    else
	git rev-parse "${branch}" > "${archdir}/${module}.new"
	if ! diff "${archdir}/${module}.new" "${archdir}/${module}.latest" > /dev/null; then
	    cat "${archdir}/${module}.new" > "${archdir}/${module}.latest"
	    changed=1
	fi
	rm -f "${archdir}/${module}.new"
    fi

    return ${changed}
}

function buildSourceCheckout() {
    local module=$1
    local branch=${build_source_branches["${module}"]}
    local repo=${build_source_repos["${module}"]}
    local archdir="${build_source_build}/${build_source_arch}"

    echo "Checking out ${module} from ${repo}"
    mkdir -p ${archdir} && cd "${archdir}" || dienow

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
    local archdir="${build_source_build}/${build_source_arch}"
    local moduledir="${archdir}/${module}"
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

# Reports exit status 0 if nothing has changed and 1 if the module
# was freshly checked out or changed.
#
function buildSourceDownload() {
    local module=$1
    local changed=0
    local archdir="${build_source_build}/${build_source_arch}"

    build_source_current=${module}

    if [ -d "${archdir}/${module}" ]; then
	buildSourceUpdate ${module}
    else
	buildSourceCheckout ${module}
    fi

    # Check if the checkout was changed
    buildSourceTrackChanges ${module}
    changed=$?

    build_source_current=

    return $changed
}

#
# Build a source by name, calling it's build_func
#  $1 module name to build
#  $2 whether the git checkout has changed (0 if unchanged)
#
function buildSourceBuild() {
    local module=$1
    local changed=$2

    build_source_current=${module}
    ${build_source_funcs["${module}"]} "${module}" "${changed}"
    build_source_current=
}

#
# Run the build
#
#  $1 - Amount of required disk space for the build, in gigabytes (optional)
#
# If the required disk space is not provided, no cleanup will be attempted
#
function buildSourceRun() {
    local headroom_gb=$1
    local module
    local arch

    if [ ! -z "${headroom_gb}" ]; then
	ensureHeadroomGigabytes ${headroom_gb}
    fi

    # Loop over the arches and set build_source_arch
    # for each iteration
    for arch in ${BUILD_ARCHES[@]}; do

	# Reset the arch for each iteration
	build_source_arch=${arch}

	if [ ! -z "${build_source_target}" ]; then
	    buildSourceDownload "${build_source_target}"
	    if ! buildSourceBuild "${build_source_target}" "$?"; then
                continue; # Some failures are fatal for the entire arch
            fi
	else
	    for module in "${build_source_modules[@]}"; do
		buildSourceDownload "${module}"
                if ! buildSourceBuild "${module}" "$?"; then
                    continue; # Some failures are fatal for the entire arch
                fi
	    done
	fi
    done
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
#   [ ${module} (${branch}) - ${build_source_arch} ] <message>: Log file location
#
function notifyIrcTarget() {
    local module=$1
    local message_type=$2
    local short_log=$3
    local message=$4
    local branch=${build_source_branches["${module}"]}
    local irc_targets=(${build_source_irc_targets[${module}]})

    # Unconditionally send the message to stdout so it gets into the logs
    echo "[ ${module} (${branch}) - ${build_source_arch} ] ${message}: ${short_log}"

    # Just early return if this module is not configured for IRC notifications
    if ! (( ${#irc_targets[@]} )); then
	echo "No IRC target configured for ${module}, not sending notification"
	return
    fi

    local full_log=${BUILD_URL}/${build_source_logdir#${build_source_export}}/${short_log}
    local full_message="[ ${module} (${branch}) - ${build_source_arch} ] ${message}: ${full_log}"

    for irc_target in ${irc_targets[@]}; do
	local irc_server=${IRC_TARGET_SERVER["${irc_target}"]}
	local irc_port=${IRC_TARGET_PORT["${irc_target}"]}
	local irc_channel=${IRC_TARGET_CHANNEL["${irc_target}"]}
	local irc_nick=${IRC_TARGET_NICK["${irc_target}"]}
	local irc_join=${IRC_TARGET_JOIN["${irc_target}"]}
	local irc_filter=${IRC_TARGET_FILTER["${irc_target}"]}

	# Filter out undesired message types for this IRC target
	if ! wordInList "${message_type}" "${irc_filter}"; then
	    continue
	fi

	local args="-s ${irc_server} -p ${irc_port} -c ${irc_channel} -n ${irc_nick} -t ${message_type}"
	if [ "${irc_join}" != "yes" ]; then
	    args=${args}" --nojoin"
	fi

	# We block annoyingly because we can launch many of them at the same time otherwise,
	# also we redirect to /dev/null just incase one day there is sensitive irc login information
	# that would otherwise end up in the master build.log
	#
	${topdir}/extra/irc-notify.py ${args} "${full_message}" > /dev/null 2>&1
    done
}
