#!/bin/sh
 
# Copyright (C) 2013 Embecosm Limited.

# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>

# A script to clone all the components of the AVR32 tool chain

# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3 of the License, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.

# You should have received a copy of the GNU General Public License along
# with this program.  If not, see <http://www.gnu.org/licenses/>.          

#		    CLONE ALL AVR32 TOOL CHAIN COMPONENTS
#		    =====================================

# Run this from the tool chain directory

# Function to clone a tool. First argument is the name of the remote, second
# is the name of the tool, third the repository to clone from.
clone_tool () {
    remote=$1
    tool=$2
    repo=$3

    # Clear out anything pre-existing and clone the repo
    rm -rf ${tool}
    git clone -o ${remote} ${repo} ${tool}
}

# Clone all the AVR32 tool components. Note that we need two copies of the
# binutils-gdb repo, to allow us to work with different versions (branches) of
# binutils and gdb
clone_tool embecosm binutils http://github.com/embecosm/avr32-binutils-gdb.git
clone_tool embecosm gcc      http://github.com/embecosm/avr32-gcc.git
clone_tool embecosm newlib   http://github.com/embecosm/avr32-newlib.git
cp -rd binutils gdb

# We perhaps ought to allow an option to check out specific versions. For now
# just messages.
echo "All repositories cloned"
