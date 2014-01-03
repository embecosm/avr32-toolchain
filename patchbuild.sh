#!/bin/sh

# Copyright (C) 2013 Embecosm Limited

# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>

# This file is a script for applying AVR32 tool chain patches under git.

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

# The AVR32 tool chains are supplied as a set of patch files to be applied to
# standard GNU toolchain distributions. However none have ChangeLog
# entries. This script applies the patches in turn, creating ChangeLog entries
# and an appropriate git log entry.

# Takes three arguments, the tool on which we are working, the patch directory
# and the top level directory to be patched.

#   ./patchbuild.sh <tool> <patchdir> <srcdir>

tool=$1
patchdir=$2
srcdir=$3
tmpf=/tmp/avr$$
tmpm=/tmp/avrmess$$
subdirs="bfd binutils config gas gdb gcc include ld libgcc libstdc++-v3 opcodes"

# Update the relevant ChangeLog temporary file.
update_changelog () {
    fn=$1
    # Try all the likely subdirs for ChangeLogs.
    for d in ${subdirs}
    do
	if echo ${fn} | grep -q "^${d}/"
	then
	    # We belong in this subdir.
	    tmpcl=${tmpf}-${d}
	    touch ${tmpcl}
	    # Remove the prefix
	    nfn=`echo ${fn} | sed -e "s#${d}/##"`
	    echo "	* ${nfn}: Patches for AVR32." >> ${tmpcl}
	    return
	fi
    done

    # We belong at the toplevel.
    tmpcl=${tmpf}-toplevel
    touch ${tmpcl}
    echo "	* ${fn}: Patches for AVR32." >> ${tmpcl}
}

# Check the args
if [ $# -ne 3 ]
then
    echo "Usage: ./patchbuild.sh <tool> <patchdir> <srcdir>"
    exit 1
fi

# Ensure patchdir and srcdir are absolute.

if ! echo $patchdir | grep -q "^/"
then
    patchdir=`pwd`/${patchdir}
fi

if ! echo $srcdir | grep -q "^/"
then
    srcdir=`pwd`/${srcdir}
fi

# Generally work in the source directory
cd ${srcdir}

# Work on each patch file in turn
for p in ${patchdir}/${tool}/*.patch
do

    # Apply the patch
    if ! patch -p0 < ${p}
    then
	echo "Failed to apply patch ${p}"
	exit 1
    fi

    # Remove any previous temporary ChangeLog files
    rm -f ${tmpf}-*

    # Extract all the files being patched
    sed -n < ${p}  > ${tmpf} \
	-e 's#^diff *-[^ ]* *\(gdb-6\.7\.1\/\)\{0,1\}\(newlib-1\.16\.0\/\)\{0,1\}\(\./\)\{0,1\}\([^ ]*\).*$#\4#p'

    # Add all the files to the git repo
    xargs < ${tmpf} echo "Adding to git: "
    xargs < ${tmpf} git add

    # Extract all the files being patched to construct ChangeLogs
    sed -i -e 's/^/update_changelog /' ${tmpf}
    source ${tmpf}

    # Update each ChangeLog, creating a git log message as we go.
    b=`basename ${p}`
    summary="AVR32 patch ${b%%.patch}"
    echo "${summary}" > ${tmpm}
    for tcf in ${tmpf}-*
    do
	d=`echo ${tcf} | sed -n -e "s#$tmpf-##p"`
	if [ "${d}" = "toplevel" ]
	then
	    d='.'
	fi
	# Build the ChangeLog
	cl=${d}/ChangeLog.AVR32
	touch ${cl}
	mv ${cl} ${tmpf}
	echo "2013-12-31  Jeremy Bennett  <jeremy.bennett@embecosm.com>" > ${cl}
	echo >> ${cl}
	echo "	${summary}" >>  ${cl}
	echo >> ${cl}
	cat ${tcf} >> ${cl}
	echo >> ${cl}
	cat ${tmpf} >> ${cl}

	# Build the Git message
	echo >> ${tmpm}
	if [ ${d} != "." ]
	then
	    echo ${d}: >> ${tmpm}
	fi
	cat ${tcf} >> ${tmpm}

	git add ${cl}
    done

    # Commit
    git commit -F ${tmpm}
done

rm -rf ${tmpf}*

