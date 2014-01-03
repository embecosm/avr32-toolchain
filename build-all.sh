#!/bin/sh

# Copyright (C) 2006 Atmel Corp.
# Copyright (C) 2013 Embecosm Limited

# Contributor Per Arnold Blaasmo
# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>

# This file is a script for building AVR32 tool chains under git.

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

#		     SCRIPT TO BUILD AVR32-ELF TOOL CHAIN
#		     ====================================

# Invocation Syntax

#     build-all.sh [--install-dir <install_dir>]
#                  [--symlink-dir <symlink_dir>]
#                  [--auto-pull | --no-auto-pull]
#                  [--auto-checkout | --no-auto-checkout]
#                  [--datestamp-install]
#                  [--jobs <count>] [--load <load>] [--single-thread]

# This script builds the AVR 32-bit tool chain as held in git. It is assumed
# to be run from the toolchain directory (i.e. with binutils, cgen, gcc,
# newlib and gdb as peer directories).

# This is nothing like as complex as the official build-avr32-gnu-toolchain.sh
# script, which will build dependency software and also a Linux/uClibc tool
# chain.

# The versions of the different tool components are wildly differing in
# age. GDB and newlib date from 2007, binutils from 2012, while GCC is a 2012
# patch of a 2009 release. Consequently we cannot make a unified source tree
# build, and so each component is built on its own.

# For some reason the official script builds a statically linked binutils
# for Intel Linux platforms (but not Windows). Not sure why this is, unless to
# make the tool chain movable (the RUNPATH issue). For now this script builds
# a dynamically linked tool chain.

# --install-dir <install_dir>

#     The directory in which the tool chain should be installed. Default
#     /opt/avr32.

# --symlink-dir <symlink_dir>

#     If specified, the install directory will be symbolically linked to this
#     directory. Default not specified.

#     For example it may prove useful to install in a directory named with the
#     date and time when the tools were built, and then symbolically link to a
#     directory with a fixed name. By using the symbolic link in the users
#     PATH, the latest version of the tool chain will be used, while older
#     versions of the tool chains remain available under the dated
#     directories.

# --auto-checkout | --no-auto-checkout

#     If specified, a "git checkout" will be done in each component repository
#     to ensure the correct branch is checked out. Default is to checkout.

# --auto-pull | --no-auto-pull

#     If specified, a "git pull" will be done in each component repository
#     after checkout to ensure the latest code is in use. Default is to pull.

# --datestamp-install

#     If specified, this will append a date and timestamp to the install
#     directory name. (see the comments under --symlink-dir above for reasons
#     why this might be useful).

# --jobs <count>

#     Specify that parallel make should run at most <count> jobs. The default
#     is <count> equal to one more than the number of processor cores shown by
#     /proc/cpuinfo.

# --load <load>

#     Specify that parallel make should not start a new job if the load
#     average exceed <load>. The default is <load> equal to one more than the
#     number of processor cores shown by /proc/cpuinfo.

# --single-thread

#     Equivalent to --jobs 1 --load 1000. Only run one job at a time, but run
#     whatever the load average.

# Where directories are specified as arguments, they are relative to the
# current directory, unless specified as absolute names.

# ------------------------------------------------------------------------------
# Unset variables, which if inherited as environment variables from the caller
# could cause us grief.
unset symlinkdir
unset parallel
unset datestamp
unset jobs
unset load

# Set some useful constants
VERSION=3.4.2

# Set defaults for some options
rootdir=`(cd .. && pwd)`
builddir="${rootdir}/bd-${VERSION}"
bd_binutils=${builddir}/binutils
bd_gcc_bs=${builddir}/gcc-bootstrap
bd_gcc=${builddir}/gcc
bd_newlib=${builddir}/newlib
bd_gdb=${builddir}/gdb
logdir="${rootdir}/logs-${VERSION}"
installdir="/opt/avr32"
autocheckout="--auto-checkout"
autopull="--auto-pull"
make_load="`(echo processor; cat /proc/cpuinfo 2>/dev/null) \
           | grep -c processor`"
jobs=${make_load}
load=${make_load}

# Parse options
until
opt=$1
case ${opt} in
    --install-dir)
	shift
	installdir=$1
	;;

    --symlink-dir)
	shift
	symlinkdir=$1
	;;

    --auto-checkout | --no-auto-checkout)
	autocheckout=$1
	;;

    --auto-pull | --no-auto-pull)
	autopull=$1
	;;

    --datestamp-install)
	datestamp=-`date -u +%F-%H%M`
	;;

    --jobs)
	shift
	jobs=$1
	;;

    --load)
	shift
	load=$1
	;;

    --single-thread)
	jobs=1
	load=1000
	;;

    ?*)
	echo "Unknown argument $1"
	echo
	echo "Usage: ./build-all.sh [--install-dir <install_dir>]"
	echo "                      [--symlink-dir <symlink_dir>]"
	echo "                      [--auto-checkout | --no-auto-checkout]"
        echo "                      [--auto-pull | --no-auto-pull]"
	echo "                      [--datestamp-install]"
        echo "                      [--jobs <count>] [--load <load>]"
        echo "                      [--single-thread]"
	exit 1
	;;

    *)
	;;
esac
[ "x${opt}" = "x" ]
do
    shift
done

if [ "x$datestamp" != "x" ]
then
    installdir="${installdir}${datestamp}"
fi

parallel="-j ${jobs} -l ${load}"

# Make sure we stop if something failed.
trap "echo ERROR: Failed due to signal ; date ; exit 1" \
    HUP INT QUIT SYS PIPE TERM

# Exit immediately if a command exits with a non-zero status (but note this is
# not effective if the result of the command is being tested for, so we can
# still have custom error handling).
set -e

# Change to the root directory
cd "${rootdir}"

# Set up a logfile
mkdir -p "${logdir}"
logfile="${logdir}/build-$(date -u +%F-%H%M).log"
rm -f "${logfile}"

# Checkout the correct branch for each tool
echo "Checking out GIT trees" >> "${logfile}"
echo "======================" >> "${logfile}"

echo "Checking out GIT trees ..."
if ! ${rootdir}/toolchain/avr32-versions.sh ${rootdir} ${autocheckout} \
         ${autopull} >> "${logfile}" 2>&1
then
    echo "ERROR: Failed to checkout GIT versions of tools"
    echo "- see ${logfile}"
    exit 1
fi

# Build the tool chain
echo "START AVR32 TOOLCHAIN BUILD: $(date)" >> "${logfile}"
echo "START AVR32 TOOLCHAIN BUILD: $(date)"

echo "Installing in ${installdir}" >> "${logfile}" 2>&1
echo "Installing in ${installdir}"

# We'll need the tool chain on the path.
PATH=${installdir}/bin:$PATH
export PATH

# Configure binutils
echo "Configuring binutils" >> "${logfile}"
echo "====================" >> "${logfile}"

echo "Configuring binutils ..."

# Create and change to the build dir
rm -rf "${bd_binutils}"
mkdir -p "${bd_binutils}"
cd "${bd_binutils}"

# Configure the build
if "${rootdir}/binutils"/configure --target=avr32 \
        --disable-nls --disable-werror \
        --with-pkgversion="AVR32 toolchain ${VERSION} (built $(date +%Y%m%d))" \
        --with-bugurl="http://www.atmel.com/avr" \
        --prefix=${installdir} >> "${logfile}" 2>&1
then
    echo "  finished configuring binutils"
else
    echo "ERROR: binutils configure failed."
    echo "- see ${logfile}"
    exit 1
fi

# Build binutils
echo "Building binutils" >> "${logfile}"
echo "=================" >> "${logfile}"

echo "Building binutils ..."

# Per Arnold magic to get headers to reconfigure. We really need to get this
# sorted properly, so plain make works OK.
if make ${parallel} all-bfd TARGET-bfd=headers >> "${logfile}" 2>&1
then
    echo "  finished building BFD headers"
else
    echo "ERROR: BFD headers build failed."
    echo "- see ${logfile}"
    exit 1
fi

# Force reconfig of bfd
rm -f bfd/Makefile

# Build
cd "${bd_binutils}"
if make ${parallel} all-build all-binutils all-gas all-ld >> "${logfile}" 2>&1
then
    echo "  finished building binutils"
else
    echo "ERROR: binutils build failed."
    echo "- see ${logfile}"
    exit 1
fi

# Install binutils
echo "Installing binutils" >> "${logfile}"
echo "===================" >> "${logfile}"

echo "Installing binutils ..."

# Install
cd "${bd_binutils}"
if make install-binutils install-gas install-ld >> "${logfile}" 2>&1
then
    echo "  finished installing binutils"
else
    echo "ERROR: binutils install failed."
    echo "- see ${logfile}"
    exit 1
fi

# Configure gcc bootstrap (pre-Newlib)
echo "Configuring gcc (bootstrap)" >> "${logfile}"
echo "===========================" >> "${logfile}"

echo "Configuring gcc (bootstrap) ..."

# Create and change to the build dir
rm -rf "${bd_gcc_bs}"
mkdir -p "${bd_gcc_bs}"
cd "${bd_gcc_bs}"

# Configure the build
if "${rootdir}/gcc"/configure --target=avr32 \
        --disable-libssp --disable-shared \
        --disable-threads --disable-nls \
        --disable-libstdcxx-pch --without-headers \
        --enable-languages=c \
        --with-pkgversion="AVR32 toolchain ${VERSION} (built $(date +%Y%m%d))" \
        --with-bugurl="http://www.atmel.com/avr" \
        --prefix=${installdir} >> "${logfile}" 2>&1
then
    echo "  finished configuring gcc (bootstrap)"
else
    echo "ERROR: gcc (bootstrap) configure failed."
    echo "- see ${logfile}"
    exit 1
fi

# Build gcc bootstrap version
echo "Building gcc (bootstrap)" >> "${logfile}"
echo "========================" >> "${logfile}"

echo "Building gcc (bootstrap) ..."

# Build. There seems to be an issue with GCC 4.4 and Graphite if the PPL
# library is not explicitly placed on the command line.
cd "${bd_gcc_bs}"
if make LDFLAGS+=-lppl_c ${parallel} all-build all-gcc \
        all-target-libgcc >> "${logfile}" 2>&1
then
    echo "  finished building gcc (bootstrap)"
else
    echo "ERROR: gcc (bootstrap) build failed."
    echo "- see ${logfile}"
    exit 1
fi

# Install gcc
echo "Installing gcc (bootstrap)" >> "${logfile}"
echo "==========================" >> "${logfile}"

echo "Installing gcc (bootstrap) ..."

# Install
cd "${bd_gcc_bs}"
if make install-gcc install-target-libgcc >> "${logfile}" 2>&1
then
    echo "  finished installing gcc (bootstrap)"
else
    echo "ERROR: gcc (bootstrap) install failed."
    echo "- see ${logfile}"
    exit 1
fi

# Configure newlib
echo "Configuring newlib" >> "${logfile}"
echo "==================" >> "${logfile}"

echo "Configuring newlib ..."

# Create and change to the build dir
rm -rf "${bd_newlib}"
mkdir -p "${bd_newlib}"
cd "${bd_newlib}"

# Configure the build
if "${rootdir}/newlib"/configure --target=avr32 \
        --enable-newlib-io-long-long \
        --enable-newlib-io-long-double \
        --enable-newlib-io-pos-args \
        --enable-newlib-reent-small \
        --enable-target-optspace \
        --with-pkgversion="AVR32 toolchain ${VERSION} (built $(date +%Y%m%d))" \
        --with-bugurl="http://www.atmel.com/avr" \
        --prefix=${installdir} >> "${logfile}" 2>&1
then
    echo "  finished configuring newlib"
else
    echo "ERROR: newlib configure failed."
    echo "- see ${logfile}"
    exit 1
fi

# Build newlib
echo "Building newlib" >> "${logfile}"
echo "========================" >> "${logfile}"

echo "Building newlib ..."

# Build
cd "${bd_newlib}"
if make ${parallel} all-target-libgloss all-target-newlib >> "${logfile}" 2>&1
then
    echo "  finished building newlib"
else
    echo "ERROR: newlib build failed."
    echo "- see ${logfile}"
    exit 1
fi

# Install newlib
echo "Installing newlib" >> "${logfile}"
echo "==========================" >> "${logfile}"

echo "Installing newlib ..."

# Install
cd "${bd_newlib}"
if make install-target-libgloss install-target-newlib >> "${logfile}" 2>&1
then
    echo "  finished installing newlib"
else
    echo "ERROR: newlib install failed."
    echo "- see ${logfile}"
    exit 1
fi

# Configure gcc full (post-Newlib)
echo "Configuring gcc (full)" >> "${logfile}"
echo "======================" >> "${logfile}"

echo "Configuring gcc (full) ..."

# Create and change to the build dir
rm -rf "${bd_gcc}"
mkdir -p "${bd_gcc}"
cd "${bd_gcc}"

# Configure the build
if "${rootdir}/gcc"/configure --target=avr32 \
        --disable-libssp --disable-shared \
        --disable-threads --disable-nls \
        --disable-libstdcxx-pch --without-headers \
        --enable-languages=c,c++ \
        --with-dwarf2 \
        --enable-__cxa_atexit --disable-shared --with-newlib \
        --enable-version-specific-runtime-libs \
        --disable-shared \
        --with-pkgversion="AVR32 toolchain ${VERSION} (built $(date +%Y%m%d))" \
        --with-bugurl="http://www.atmel.com/avr" \
        --prefix=${installdir} >> "${logfile}" 2>&1
then
    echo "  finished configuring gcc (full)"
else
    echo "ERROR: gcc (full) configure failed."
    echo "- see ${logfile}"
    exit 1
fi

# Build gcc full version
echo "Building gcc (full)" >> "${logfile}"
echo "===================" >> "${logfile}"

echo "Building gcc (full) ..."

# Build. Once again with explicit PPL library (see above)
cd "${bd_gcc}"
if make LDFLAGS+=-lppl_c  ${parallel} all-build all-gcc all-target-libgcc \
        all-target-libstdc++-v3 >> "${logfile}" 2>&1
then
    echo "  finished building gcc (full)"
else
    echo "ERROR: gcc (full) build failed."
    echo "- see ${logfile}"
    exit 1
fi

# Install gcc
echo "Installing gcc (full)" >> "${logfile}"
echo "=====================" >> "${logfile}"

echo "Installing gcc (full) ..."

# Install
cd "${bd_gcc}"
if make install-gcc install-target-libgcc install-target-libstdc++-v3 \
        >> "${logfile}" 2>&1
then
    echo "  finished installing gcc (full)"
else
    echo "ERROR: gcc (full) install failed."
    echo "- see ${logfile}"
    exit 1
fi

# Configure gdb
echo "Configuring gdb" >> "${logfile}"
echo "===============" >> "${logfile}"

echo "Configuring gdb ..."

# Create and change to the build dir
rm -rf "${bd_gdb}"
mkdir -p "${bd_gdb}"
cd "${bd_gdb}"

# Configure the build
if "${rootdir}/gdb"/configure --target=avr32 \
        --disable-nls --disable-werror --with-python \
        --with-pkgversion="AVR32 toolchain ${VERSION} (built $(date +%Y%m%d))" \
        --with-bugurl="http://www.atmel.com/avr" \
        --prefix=${installdir} >> "${logfile}" 2>&1
then
    echo "  finished configuring gdb"
else
    echo "ERROR: gdb configure failed."
    echo "- see ${logfile}"
    exit 1
fi

# Build gdb
echo "Building gdb" >> "${logfile}"
echo "============" >> "${logfile}"

echo "Building gdb ..."

# Build
cd "${bd_gdb}"
if make ${parallel} all-build all-gdb all-sim >> "${logfile}" 2>&1
then
    echo "  finished building gdb"
else
    echo "ERROR: gdb build failed."
    echo "- see ${logfile}"
    exit 1
fi

# Install gdb
echo "Installing gdb" >> "${logfile}"
echo "==============" >> "${logfile}"

echo "Installing gdb ..."

# Install
cd "${bd_gdb}"
if make install-gdb install-sim >> "${logfile}" 2>&1
then
    echo "  finished installing gdb"
else
    echo "ERROR: gdb install failed."
    echo "- see ${logfile}"
    exit 1
fi

# All tools built
echo "DONE AVR32: $(date)" >> "${logfile}"
echo "DONE AVR32: $(date)"
echo  "- see ${logfile}"

# Link to the defined place. Note the introductory comments about the need to
# specify explicitly the install directory.
if [ "x${symlinkdir}" != "x" ]
then
    rm -f ${symlinkdir}
    ln -s ${installdir} ${symlinkdir}
fi
