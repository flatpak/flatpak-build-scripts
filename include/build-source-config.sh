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

#
# Declare arrays used in the config file
#

# List of IRC targets and associative arrays
IRC_TARGET_LIST=()
declare -A IRC_TARGET_SERVER
declare -A IRC_TARGET_PORT
declare -A IRC_TARGET_CHANNEL
declare -A IRC_TARGET_NICK
declare -A IRC_TARGET_JOIN

# Various build type lists and their
# corresponding associative arrays
BASE_SDK_LIST=()
declare -A BASE_SDK_REPO
declare -A BASE_SDK_BRANCH
declare -A BASE_SDK_VERSION
declare -A BASE_SDK_ASSETS
declare -A BASE_SDK_IRC_TARGET

SDK_LIST=()
declare -A SDK_REPO
declare -A SDK_BRANCH
declare -A SDK_VERSION
declare -A SDK_ASSETS
declare -A SDK_IRC_TARGET

APP_LIST=()
declare -A APP_REPO
declare -A APP_BRANCH
declare -A APP_VERSION
declare -A APP_ASSETS
declare -A APP_IRC_TARGET

# Source the actual config which will populate the arrays
. ${arg_config}
