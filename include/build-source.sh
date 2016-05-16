#
# An ordered table of sources with abstract
# build functions.
#
build_source_modules=()
declare -A build_source_repos
declare -A build_source_branches
declare -A build_source_funcs

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
#
function buildSourceAdd() {
    local module=$1
    local repo=$2
    local branch=$3
    local build_func=$4

    build_source_modules+=("${module}")
    build_source_repos["${module}"]="$repo"
    build_source_branches["${module}"]="$branch"
    build_source_funcs["${module}"]=${build_func}
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
