#!/bin/bash
########################################################################
# build-avr32-gnu-tools.sh
#
# This script takes care of building the compiler, debugger, and
# utilities required for building AVR32 applications.
#
# Copyright (C) 2006 Atmel Corp.
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation version 2.1.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this script; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
########################################################################
#
# $Id:build-avr32-gnu-toolchain.sh 35655 2008-01-02 10:17:53Z pablaasmo $
#
########################################################################

usage="\
Usage: `basename $0` [OPTIONS] <package...>

This script takes care of building the compiler, debugger and
utilities required for building AVR32 applications.

Packages can be given as arguments. The order they are given defines the
build order. Use option '-l' to list default packages.

The script build the tools in the 'build' folder based on the sources in the
'source' folder. The tools are installed in the 'prefix' folder.
Default 'build' folder is a '<current>/build'. Change it with option '-b <folder>'.
Default 'source' folder is '<current>'. Change it with option 's <folder>'.
Default 'prefix' folder is '/usr/local'. Change it by setting enviroment 'AVR32_PREFIX',
                                         or use option '-p <prefix>'.

Options:
  -b <folder>           Defines build folder
  -h                    Prints this help message
  -k                    Keep old build folder
  -l                    Lists default packages
  -p <prefix>           Sets the installation prefix
  -P <password>			The password for executing sudo command
  -s <folder>           Defines source folder

  -B <target>           sets build platform for 'configure'
  -H <target>           sets host platform for 'configure'

Enviroment:
  AVR32_PREFIX          Installation prefix
  AVR_32_GNU_TOOLCHAIN_VERSION Sets a local version number.

  BUILD_NUMBER          Adds a build number to version string.
                        Default is date of build."

######## General helper functions ###############################
function task_start () {
    printf "%-52s" "$1"
}

function task_success () {
    echo OK
}

function task_error () {
    echo FAILED
    echo $1
    exit 1
}

function wipe_directory () {
    if [ -e "$1" ]; then
        task_start "Wiping $1 ($2)... "
        rm -rf "$1" && task_success || task_error
    fi
}

function do_make () {
    make $MAKEOPTS > make.out 2>&1 || task_error "$1"
}

function do_make_install () {
    if test -z ${SUDO_PASSWORD}
    then
        make install > make.install.out 2>&1 || task_error "$1"
    else
        echo ${SUDO_PASSWORD}| sudo -S -E PATH=${PATH}:${PREFIX}/bin \
        make install > make.install.out 2>&1 || task_error "$1"
    fi
}

function do_pushd () {
    pushd $1 > /dev/null
}

function do_popd () {
    popd $1 > /dev/null
}

function do_mkpushd () {
    mkdir -p $1
    do_pushd $1
}

function start_timer () {
    begin_time=`date +%s`
}

function end_timer () {
    end_time=`date +%s`
}

function report_time() {
    elapsed=$[$end_time - $begin_time]
    hours=$[$elapsed/3600]
    mins=$[($elapsed%3600)/60]
    secs=$[$elapsed%60]
    echo "Finished at `date`"
    echo "Task completed in $hours hours, $mins minutes and $secs seconds."
}

######## Functions for avr32 gnu toolchain ###############################
function remove_build_folder() {
# arg1 = the package subfolder in builddir
    if test -d ${builddir}/$1 -a ${KEEP_BUILD_FOLDER} != "YES" ; then
        rm -rf ${builddir}/$1 || task_error "Could not remove $1 build folder."
    fi
}

#Tries to set platform types
# $1 = package
function set_platform_variables() {
    build_platform=${srcdir}/${1}/config.guess
    if test -z ${host_platform}; then
        host_platform=${build_platform}
    fi
}

function unpack_upstream_source() {
    local workdir=$1
    local archive_name=$2
    local archive_tar_flag=""

    case $archive_name in
        *.tar.gz|*.tgz)
            archive_tar_flag='--gzip';;
        *.tar.bz2|*.tbz2)
            archive_tar_flag='--bzip2';;
        *.tar)
            archive_tar_flag="";;
        *)
            task_error "Unknown archive format."
    esac

    if ! tar --directory ${workdir} ${archive_tar_flag} -x -f ${archive_name}; then
        task_error "Corrupt file ${archive_name}"
    fi
}

function apply_patches() {
    local workdir=$1
    local archivedir=$2

    do_pushd ${workdir}

        # Patch Categories
        #    0x = Distribution specific (distro names and versions)
        #    1x = Host platform specific
        #    2x = Build system specific
        #    3x = New target features
        #    4x = Patches to fix target bugs
        #    5x = New devices

    if test -z "$(ls ${archivedir}/*.patch)"; then
        echo "No patch files, skipping patch"
        do_popd
        return
    fi

    for i in ${archivedir}/*.patch ; do
        echo "Patch: $i" >> patch.log
        patch --verbose --strip=0 --input="$i"  >> patch.log || task_error "Patching failed."
    done

    do_popd
}

############ Define functions used for the different tasks ########
function binutils_set_parameters()
{
    if test -f "${srcdir}/binutils/bfd/ATMEL-VER"; then
        read binutils_version_atmel < ${srcdir}/binutils/bfd/ATMEL-VER
    else
        binutils_version_atmel="atmel-$(date +%Y%m%d%H%M%Z)"
    fi
}

function binutils_prep() {
    if test -f ${srcdir}/binutils/.prep_done
    then
        binutils_set_parameters
        return
    fi

    task_start "Preparing Binutils... "
    if [ ! -d ${srcdir}/binutils-*-patches ] ; then
        echo "Can't find binutils source."
        exit 1
    fi
    do_pushd ${srcdir}
    rm -rf binutils binutils-[0-9]\.[0-9][0-9]* || task_error "Removing old binutils folders failed"
    upstream_source=$(ls ./binutils-*-patches/binutils-*.*)
    unpack_upstream_source ${srcdir} ${upstream_source}

    # Link the unpacked folder to a generic folder for future work
    ln -s $(ls -d binutils-[0-9]\.[0-9][0-9]*)  binutils || task_error "Error linking binutils folder"
    apply_patches ${srcdir}/binutils $(ls -d ${srcdir}/binutils-*-patches)

    # Now prepear for configuration
    if [ ! -d ${srcdir}/binutils ] ; then
        echo "Can't find binutils source."
        exit 1
    fi
    binutils_set_parameters
    cd binutils

    # Some sed magic to make autotools work on platforms with different autotools version
    # Works for binutils 2.20.1. May work for other versions.
    sed -i 's/AC_PREREQ(2.64)/AC_PREREQ(2.63)/g' ./configure.ac || task_error "sed failed"
    sed -i 's/AC_PREREQ(2.64)/AC_PREREQ(2.63)/g' ./libiberty/configure.ac || task_error "sed failed"
    sed -i 's/  \[m4_fatal(\[Please use exactly Autoconf \]/  \[m4_errprintn(\[Please use exactly Autoconf \]/g' ./config/override.m4 || task_error "sed failed"

    autoconf || task_error "autoconf failed"
    for d in bfd opcodes binutils ld gas gprof ; do
        do_pushd ${d}
        autoreconf	 || task_error "autoreconf in $d failed."
        do_popd
    done
    do_popd
    task_success
    touch ${srcdir}/binutils/.prep_done
}


# arg1 = target
function binutils_build() {
    local binutils_target=${1}
    local binutils_extra_opts=""
    local binutils_doc_opts=""
    local binutils_extra_config=""

    task_start "Building Binutils for ${binutils_target}... "
    remove_build_folder "${binutils_target}-binutils"
    OLD_MAKEOPTS=$MAKEOPTS
    MAKEOPTS=""
    do_mkpushd ${builddir}/${binutils_target}-binutils
#	build_platform=`${srcdir}/binutils/config.guess` || task_error "Error running config.guess"
    case "${host_platform}" in
    i[3456]86*-linux*)
        binutils_extra_config="LDFLAGS=-all-static"
        ;;
    x86_64*-linux*)
        binutils_extra_config="LDFLAGS=-all-static"
        ;;
    i[3456789]86*-mingw32*)
        binutils_extra_config=""
        ;;
    *)
        binutils_extra_config=""
    esac

    CFLAGS="-Os -g0" \
    ${srcdir}/binutils/configure \
        --with-pkgversion="AVR_32_bit_GNU_Toolchain_${avr_32_gnu_toolchain_version}_${BUILD_NUMBER}"\
        --with-bugurl="http://www.atmel.com/avr"\
        --target=${binutils_target} \
        --host=${host_platform} \
        --build=${build_platform} \
        --prefix=$PREFIX \
        --disable-nls \
        --disable-werror \
        > configure.out 2>&1 || task_error "configure failed. See configure.out."
    MAKEOPTS="all-bfd TARGET-bfd=headers"
    do_make "make bfd headers failed. See make.out."
    # force reconfiguring
    rm bfd/Makefile || task_error "Can't remove bfd/Makefile"
    MAKEOPTS=""
    make configure-host >> make.out 2>&1 || task_error "make configure-host failed. See make.out"
    make ${binutils_extra_config} >> make.out 2>&1 || task_error "make failed. See make.out."
    task_success
    task_start "Installing binutils for ${binutils_target}... "
    do_make_install "make install failed. See make.install.out."
    do_popd
    MAKEOPTS=$OLD_MAKEOPTS
    task_success
}

function gcc_set_parameters()
{
    if test -f "${srcdir}/gcc/gcc/BASE-VER"; then
        gcc_version_base=$(cat ${srcdir}/gcc/gcc/BASE-VER)
        case ${gcc_version_base} in
               4.[346].*)
                   if test -f "${srcdir}/gcc/gcc/ATMEL-VER"
                   then
                    read gcc_version_atmel < ${srcdir}/gcc/gcc/ATMEL-VER
                   else
                       gcc_version_atmel="atmel-$(date +%Y%m%d%H%M%Z)"
                   fi
                ;;
               4.[12].*)
                # GCC 4.1.x or 4.2.x
                      gcc_version_atmel=`grep -E "define[[:space:]]{1,}VERSUFFIX" "${srcdir}/gcc/gcc/version.c" | sed -e 's/.*"\([^"]*\)".*/\1/'`

                # Add some version specific info for certain platforms
                case ${host_platform} in
                    i68[3456]-*mingw32 )
                        sed 's/\(.*VERSUFFIX "\)\([^"]*\)/\1\2 (mingw32 special)/' ${srcdir}/gcc/gcc/version.c > ${srcdir}/gcc/gcc/version.c.new \
                            || task_error "error adding '(mingw32 special)' to gcc/version.c"
                        mv -f ${srcdir}/gcc/gcc/version.c.new ${srcdir}/gcc/gcc/version.c || task_error "error renaming gcc/version.c"
                        ;;
                    i68[3456]-*mingw64 )
                        sed 's/\(.*VERSUFFIX "\)\([^"]*\)/\1\2 (mingw64 special)/' ${srcdir}/gcc/gcc/version.c > ${srcdir}/gcc/gcc/version.c.new \
                             || task_error "error adding '(mingw64 special)' to gcc/version.c"
                        mv -f ${srcdir}/gcc/gcc/version.c.new ${srcdir}/gcc/gcc/version.c || task_error "error renaming gcc/version.c"
                        ;;
                    * )
                        ;;
                esac
                ;;
            4.0.*)
                # GCC 4.0.x
                      gcc_version_atmel=`grep version_string "gcc/version.c" | sed -e 's/.*"\([^"]*\)".*/\1/'`
                # Add some version specific info for certain platforms
                case ${host_platform} in
                    i68[3456]-*mingw32 )
                        sed 's/\(.*VERSUFFIX "\)\([^"]*\)/\1\2 (mingw32 special)/' ${srcdir}/gcc/gcc/version.c > ${srcdir}/gcc/gcc/version.c.new \
                            || task_error "error adding '(mingw32 special)' to gcc/version.c"
                        mv -f ${srcdir}/gcc/gcc/version.c.new ${srcdir}/gcc/gcc/version.c || task_error "error renaming gcc/version.c"
                        ;;
                    i68[3456]-*mingw64 )
                        sed 's/\(.*VERSUFFIX "\)\([^"]*\)/\1\2 (mingw64 special)/' ${srcdir}/gcc/gcc/version.c > ${srcdir}/gcc/gcc/version.c.new \
                             || task_error "error adding '(mingw64 special)' to gcc/version.c"
                        mv -f ${srcdir}/gcc/gcc/version.c.new ${srcdir}/gcc/gcc/version.c || task_error "error renaming gcc/version.c"
                        ;;
                    * )
                        ;;
                esac
                ;;
            *)
            echo "unsupported GCC Version ${gcc_version_base}"
            exit 1
            ;;
        esac
    else
        # Cant't get gcc version, just set something usefull.
        gcc_version_base="4.3.3"
        gcc_version_atmel="atmel-$(date +%Y%m%d%H%M%Z)"
    fi

}

function gcc_prep() {
    if test -f ${srcdir}/gcc/.prep_done
    then
        gcc_set_parameters
        return
    fi


    task_start "Preparing GCC... "
    do_pushd ${srcdir}
    rm -rf gcc gcc-[0-9]\.[0-9]\.[0-9] || task_error "Removing old gcc folders failed"
    upstream_source=$(ls ${srcdir}/gcc-*-patches/gcc-*.*.*)
    unpack_upstream_source ${srcdir} ${upstream_source}

    # Link the unpacked folder to a generic folder for futhure work
    ln -s $(ls -d gcc-[0-9]\.[0-9]\.[0-9])  gcc || task_error "Error linking gcc folder"
    apply_patches ${srcdir}/gcc $(ls -d ${srcdir}/gcc-*-patches)

    # Now prepear for configuration
    if [ ! -d ${srcdir}/gcc ] ; then
        echo "Can't find gcc source."
        exit 1
    fi
    gcc_set_parameters

    cd gcc
    case ${gcc_version_base} in
         4.[346].*)
            # Some sed magic to make autotools work on platforms with different autotools version
            sed -i 's/m4_copy(\[AC_PREREQ\]/m4_copy_force(\[AC_PREREQ\]/g' ./config/override.m4 || task_error "sed failed"
            sed -i 's/m4_copy(\[_AC_PREREQ\]/m4_copy_force(\[_AC_PREREQ\]/g' ./config/override.m4 || task_error "sed failed"
            sed -i 's/  \[m4_fatal(\[Please use exactly Autoconf \]/  \[m4_errprintn(\[Please use exactly Autoconf \]/g' ./config/override.m4 || task_error "sed failed"

            autoconf || task_error "autoconf failed"
            # Running autoreconf in libstdc++ does not seem to be necessary in 4.3.x
            # and it causes some problems on platform with auto-tool >2.61
            ;;
         4.[012].*)
            ${AUTOCONF213_EXE} || task_error "autoconf failed"
            # TODO: Check if this autoreconf is necessary?
            # I do not remember why we have to do this in libstdc++
            # Its here because it has "always" been here.
            do_pushd libstdc++-v3
            autoreconf || task_error "libstdc++-v3 autoreconf failed"
            do_popd
            ;;
        *)
            echo "Unsupported GCC version ${gcc_version_base}"
            exit 1
            ;;
    esac
    do_popd
    task_success
    touch ${srcdir}/gcc/.prep_done
}

# Building of gcc has to bee done in 2 steps. This is first step.
# arg1 = target
# arg2 = extra options
function gcc_build_bootstrap() {
    task_start "Building bootstrap GCC for $1... "
    remove_build_folder "${1}-gcc-bootstrap"
    OLD_MAKEOPTS=$MAKEOPTS
    MAKEOPTS=""
    do_mkpushd ${builddir}/${1}-gcc-bootstrap
    # Are we doing a canadian cross?

    if ${canadian_cross}; then
        EXTRAOPTS="--disable-win32-registry --enable-sjlj-exceptions"
        #export LDFLAGS="-L ${PREFIX}/lib"
        #export CPPFLAGS="-I ${PREFIX}/include"
    else
        EXTRAOPTS=""
    fi
    case ${gcc_version_base} in
         4.[346].*)
        EXTRAOPTS="${EXTRAOPTS} \
                   --with-pkgversion="AVR_32_bit_GNU_Toolchain_${avr_32_gnu_toolchain_version}_${BUILD_NUMBER}" \
                   --with-bugurl="http://www.atmel.com/avr"
                  "
        ;;

         *)
         # Do nothing
         ;;
    esac
    ${srcdir}/gcc/configure \
        --target=$1 \
        --host=${host_platform} \
        --build=${build_platform} \
        --prefix=${PREFIX} \
        ${EXTRAOPTS} \
        --disable-libssp \
        --disable-shared \
        --disable-threads \
        --disable-nls \
           --disable-libstdcxx-pch \
        --without-headers \
        --enable-languages=c \
        --with-mpfr-lib=${PREFIX}/lib \
        --with-mpfr-include=${PREFIX}/include \
        --with-gmp=${PREFIX} \
        --with-mpc=${PREFIX} \
        $2 \
        > configure.out 2>&1 || task_error "configure failed. See configure.out."
    do_make "Building failed. See make.out."
    task_success
    task_start "Installing bootstrap GCC for $1... "
    do_make_install "Installing failed. See make.install.out."
    do_popd
    MAKEOPTS=$OLD_MAKEOPTS
    task_success
}


# This is second step off building gcc. This is done after newlib has been buildt.
# arg1 = target
# arg2 = extra options
function gcc_build_full()
{
    local gcc_target=${1}
    local gcc_extra_opts="${2}"
    local gcc_doc_opts=""
    local gcc_extra_config=""

    task_start "Building full GCC for ${gcc_target}... "
    remove_build_folder "${gcc_target}-gcc-full"
    OLD_MAKEOPTS=$MAKEOPTS
    MAKEOPTS=""
    do_mkpushd ${builddir}/${gcc_target}-gcc-full
    # Are we doing a canadian cross?
    if ${canadian_cross}; then
        case ${host_platform} in
            i68[3456]-*mingw32 )
                gcc_extra_opts="${gcc_extra_opts} --enable-win32-registry=avr32toolchain --enable-sjlj-exceptions"
                #export LDFLAGS="-L ${PREFIX}/lib"
                #export CPPFLAGS="-I ${PREFIX}/include"

                ;;
            * )
                ;;
        esac
    fi
    case ${gcc_version_base} in
        4.[346].*)
        gcc_extra_opts="${gcc_extra_opts} \
                   --with-pkgversion="AVR_32_bit_GNU_Toolchain_${avr_32_gnu_toolchain_version}_${BUILD_NUMBER}" \
                   --with-bugurl="http://www.atmel.com/avr"
                  "
        ;;

         *)
         # Do nothing
         ;;
    esac

    case "${host_platform}" in
        i[3456]86*-linux*)
            gcc_extra_config="LDFLAGS=-static"
            ;;
        x86_64*-linux*)
            gcc_extra_config="LDFLAGS=-static"
            ;;
        i[3456789]86*-mingw32*)
            gcc_extra_config=""
            ;;
        *)
            gcc_extra_config=""
    esac

    langspec="c,c++"
    CFLAGS="-Os -g0" \
    ${srcdir}/gcc/configure \
        --target=${gcc_target} \
        --host=${host_platform} \
        --build=${build_platform} \
        --prefix=${PREFIX} \
        --enable-languages=$langspec \
        --disable-nls \
        --disable-libssp \
        --disable-libstdcxx-pch \
        --with-dwarf2 \
        --enable-version-specific-runtime-libs \
        --disable-shared \
        --enable-doc \
        --with-mpfr-lib=${PREFIX}/lib \
        --with-mpfr-include=${PREFIX}/include \
        --with-gmp=${PREFIX} \
        --with-mpc=${PREFIX} \
        ${gcc_extra_opts} \
        > configure.out 2>&1 || task_error "configure failed. See configure.out."
    make ${gcc_extra_config} >> make.out 2>&1 || task_error "make failed. See make.out."
    task_success
    task_start "Installing full GCC for ${gcc_target} ..."
    do_make_install "make install failed. See make.install.out."
    do_popd
    MAKEOPTS=$OLD_MAKEOPTS
    task_success
}

function newlib_prep() {
    if test -f ${srcdir}/newlib/.prep_done
    then
        return
    fi

    task_start "Preparing newlib... "
    do_pushd ${srcdir}
    rm -rf newlib newlib-[0-9]\.[0-9]*\.[0-9] || task_error "Removing old newlib folders failed"
    upstream_source=$(ls ${srcdir}/newlib-*-patches/newlib-*.*.*)
    unpack_upstream_source ${srcdir} ${upstream_source}

    # Link the unpacked folder to a generic folder for futhure work
    ln -s $(ls -d newlib-[0-9]\.[0-9]*\.[0-9])  newlib || task_error "Error linking gcc folder"
    apply_patches ${srcdir}/newlib $(ls -d ${srcdir}/newlib-*-patches)

    if [ ! -d ${srcdir}/newlib ] ; then
        echo "Can't find newlib source."
        exit 1
    fi
    cd ${srcdir}/newlib
    for i in newlib/libc/machine/avr32 newlib/libc/machine newlib/libc/sys/avr32 newlib/libc/sys; do
    do_pushd $i
        aclocal -I ../.. -I ../../.. -I ../../../.. || task_error "Newlib aclocal failed in $i."
        autoconf || task_error "Newlib autoconf failed in $i."
        automake --cygnus Makefile || task_error "Newlib automake failed in $i."
    do_popd
    done

    do_popd
    task_success
    touch ${srcdir}/newlib/.prep_done
}

function newlib_build() {
    task_start "Building newlib for avr32... "
    remove_build_folder "newlib"
    OLD_MAKEOPTS=$MAKEOPTS
    MAKEOPTS=""
    do_mkpushd ${builddir}/newlib
    ${srcdir}/newlib/configure \
        --target=avr32 \
        --host=${host_platform} \
        --build=${build_platform} \
        --prefix="$PREFIX" \
        --with-docdir=share/doc/newlib \
        --with-pdfdir=share/doc/newlib/pdf \
        --with-htmldir=share/doc/newlib/html \
        --enable-newlib-io-long-long \
        --enable-newlib-io-long-double \
        --enable-newlib-io-pos-args \
        --enable-newlib-reent-small \
        --enable-target-optspace \
        --enable-doc \
        > configure.out 2>&1 || \
        task_error "configure failed. See configure.out"
    do_make "Building failed. See make.out."
    task_success
    task_start "Installing newlib for avr32... "
    do_make_install "Installing newlib failed. See make.install.out."
    do_popd
    MAKEOPTS=$OLD_MAKEOPTS
    task_success
}


function ncurses_prep() {
    upstream_source=$(ls ${srcdir}/ncurses-*)
    unpack_upstream_source ${srcdir} ${upstream_source}

    # Link the unpacked folder to a generic folder for futhure work
    ln -s $(ls -d ncurses-[0-9]\.[0-9])  ncurses || task_error "Error linking ncurses folder"

}

function ncurses_build() {
    task_start "Building newlib for avr32... "
    remove_build_folder "ncurses"
    do_mkpushd ${builddir}/ncurses

    case "${host_platform}" in
        i[3456]86*-linux*)
            export LDFLAGS="-static"
            ;;
        x86_64*-linux*)
            export LDFLAGS="-static"
            ;;
        i[3456789]86*-mingw32*)
            export LDFLAGS=""
            ;;
        *)
            export LDFLAGS=""
    esac

    ${srcdir}/ncurses/configure \
          --build=${build_platform} \
          --host=${host_platform} \
          --with-build-cflags= -pipe \
          --prefix=${PREFIX}
          --without-shared \
          --without-sysmouse \
          --without-progs \
          --enable-termcap \
          --without-ada \
        > configure.out 2>&1 || \
        task_error "configure failed. See configure.out"

    do_make "Building failed. See make.out"
    task_success
    task_start "Installing ncurses... "
    do_make_install "Installing ncurses failed. See make.install.out."
    do_popd
    MAKEOPTS=$OLD_MAKEOPTS
    task_success
}

function gdb_set_parameters()
{
    if test -f "${srcdir}/gdb/bfd/ATMEL-VER"; then
        read gdb_version_atmel < ${srcdir}/gdb/bfd/ATMEL-VER
    else
        gdb_version_atmel="atmel-$(date +%Y%m%d%H%M%Z)"
    fi
}

function gdb_prep() {
    if test -f ${srcdir}/gdb/.prep_done
    then
        gdb_set_parameters
        return
    fi

    task_start "Preparing GDB... "
    do_pushd ${srcdir}
    rm -rf gdb gdb-[0-9]\.[0-9]*\.[0-9]* || task_error "Removing old gdb folders failed"
    upstream_source=$(ls ${srcdir}/gdb-*-patches/gdb-*.*.*)
    unpack_upstream_source ${srcdir} ${upstream_source}

    # Link the unpacked folder to a generic folder for futhure work
    ln -s $(ls -d gdb-[0-9]\.[0-9]*\.[0-9]*)  gdb || task_error "Error linking gcc folder"
    apply_patches ${srcdir}/gdb $(ls -d ${srcdir}/gdb-*-patches)
    popd

    if [ ! -d ${srcdir}/gdb ] ; then
        echo "Can't find gdb source."
        exit 1
    fi
    gdb_set_parameters
    do_pushd ${srcdir}/gdb
    # Have to use libtoolize to make it build on newer autotools.
    libtoolize --force --recursive  || task_error "libtoolize failed"
    autoconf || task_error "autoconf failed"
    for d in bfd opcodes gdb gdb/gdbserver; do
        do_pushd $d
        libtoolize --force # gdb folder gives an error but we ignore errors from this
        autoreconf  || task_error "autoreconf in $d failed."
        do_popd
    done
    do_popd
    task_success
    touch ${srcdir}/gdb/.prep_done

}

function gdb_build() {
    task_start "Building GDB for $1... "
    remove_build_folder "${1}-gdb"
    OLD_MAKEOPTS=$MAKEOPTS
    MAKEOPTS=""
    do_mkpushd ${builddir}/${1}-gdb
    # Are we doing a canadian cross?
    if ${canadian_cross}; then
        case ${host_platform} in
            i[3456]86-*mingw32 )
                export LDFLAGS="-L${PREFIX}/lib"
                export CPPFLAGS="-I${PREFIX}/include"
                ;;
            i[3456]86*-linux*)
                export LDFLAGS="-static"
                ;;
            * )
                ;;
        esac
    else
        export LDFLAGS="-static"
    fi

    # only from version 7.0 is --with-pkgversion and bugurls supported
    CFLAGS="-I${PREFIX}/include -L${PREFIX}/lib" \
    ${srcdir}/gdb/configure \
        --with-pkgversion="${gdb_version_atmel}-${platform_version}"\
        --with-bugurl="http://www.atmel.com/avr32"\
        --target=$1 \
        --host=${host_platform} \
        --build=${build_platform} \
        --prefix="$PREFIX" \
        --disable-nls \
        --disable-werror \
        > configure.out 2>&1 \
        || task_error "configure for $1 failed. See configure.out"
    MAKEOPTS="all-bfd TARGET-bfd=headers"
    do_make "make bfd headers failed. See make.out."
    # force reconfiguring
    rm bfd/Makefile || task_error "Can't remove bfd/Makefile"
    MAKEOPTS=""
    do_make "Building for $1 failed. See make.out."
    task_success
    task_start "Installing GBD for $1... "
    do_make_install "Installing GDB for $1 failed. See make.install.out."
    do_popd
    MAKEOPTS=$OLD_MAKEOPTS
    task_success
}

######## Functions for avr32-linux cross compiler ####################
function uclibc_prep() {
    if test -d ${builddir}/uClibc
    then
        task_start "Removing old build folder for uClibc... "
        rm -rf ${builddir}/uClibc \
            || task_error "Could not remove old build folder for uClibc."
        task_success
    fi
    task_start "Unpacking and patching uClibc... "
    mkdir -p ${builddir}/uClibc || task_error "Can't make build folder uClibc"
    tar --bzip2 --strip-components=1 --extract --directory ${builddir}/uClibc --file ${srcdir}/uclibc/uClibc-*.tar.bz2 || task_error "tar failed."
    do_pushd ${builddir}/uClibc

    sed -e s,^CROSS_COMPILER_PREFIX=.*,CROSS_COMPILER_PREFIX=\"avr32-linux-\",g \
        -e s,^KERNEL_HEADERS=.*,KERNEL_HEADERS=\"${builddir}/linux/include\",g \
        -e s,^RUNTIME_PREFIX=.*,RUNTIME_PREFIX=\"/avr32-linux/\",g \
        -e s,^DEVEL_PREFIX=.*,DEVEL_PREFIX=\"/avr32-linux/\",g \
        -e s,^SHARED_LIB_LOADER_PREFIX=.*,SHARED_LIB_LOADER_PREFIX=\"/lib\",g \
        ${srcdir}/uclibc/uClibc.config.avr32 > .config 2>/dev/null \
        || task_error "sed failed"

    do_popd
    task_success
}


function uclibc_build() {
    task_start "Building uClibc... "
    if ! test -d ${builddir}/uClibc
    then
        task_error "build folder is not present."
    fi
    do_pushd ${builddir}/uClibc
    make oldconfig > make.oldconfig.out 2>&1 \
        || task_error "make  oldconfig failed. See make.oldconfig.out"
    make -j 4 all > make.out 2>&1 \
        || task_error "make failed. See make.out"
    # Have to set '/' at the end of prefix for uclibc.
    make PREFIX="${PREFIX}/" \
         install > make.install.out 2>&1 \
        || task_error "make install failed. See make.install.out"
    do_popd
    task_success
}

# We only need to prep the kernel and build the kernel headers to build uClibc
function prep_kernel() {
    if test -d ${builddir}/linux
    then
        task_start "Removing old build folder for Linux... "
        rm -rf ${builddir}/linux \
            || task_error "Could not remove old build folder for Linux"
        task_success
    fi
    task_start "Unpacking and patching Linux kernel... "
    mkdir -p ${builddir}/linux || task_error "Can't make build folder linux"
    tar --bzip2 --extract --directory ${builddir}/linux --file ${srcdir}/linux/linux-headers-*.tar.bz2 || task_error "tar failed."
    task_success
}

function mpfr_prep() {
    task_start "Unpacking mpfr... "
    tar --extract --ungzip --directory ${builddir} --file ${srcdir}/mpfr/mpfr*.tar.gz ||\
     task_error "Failed to unpack mpfr"
    task_success
}


function mpfr_build() {

    task_start "Building libmpfr ..."
    remove_build_folder "mpfr"
    do_mkpushd ${builddir}/mpfr

    CFLAGS="-fPIC" $(ls -d ${builddir}/mpfr-*)/configure \
        --build=${build_platform} \
        --host=${host_platform} \
        --prefix=${PREFIX} \
        --with-gmp=${PREFIX} \
        --disable-shared \
        --enable-static \
        > configure.out 2>&1 || task_error "configure failed. See configure.out."

    do_make  "Failed building libmphr. See make.out"
    task_success
    task_start "Installing mpfr ..."
    do_make_install "make install failed. See make.install.out."
    do_popd
    task_success

}

function gmp_prep() {
    task_start "Unpacking gmp... "
    upstream_source=$(ls ${srcdir}/gmp/gmp*)
    unpack_upstream_source ${srcdir} ${upstream_source}
    task_success
}


function gmp_build() {

    task_start "Building libgmp ..."
    remove_build_folder "gmp"
    do_mkpushd ${builddir}/gmp

    CC_FOR_BUILD="gcc" CFLAGS="-fPIC" $(ls -d ${srcdir}/gmp-[0-9].*)/configure \
        --build=${build_platform} \
        --host=${host_platform} \
        --disable-shared \
        --enable-static \
        --prefix=${PREFIX} \
        > configure.out 2>&1 || task_error "configure failed. See configure.out."

    do_make  "Failed building libgmp. See make.out"
    task_success
    task_start "Installing gmp ..."
    do_make_install "make install failed. See make.install.out."
    do_popd
    task_success

}

function mpc_prep() {
    task_start "Unpacking mpc... "
    upstream_source=$(ls ${srcdir}/mpc/mpc*)
    unpack_upstream_source ${srcdir} ${upstream_source}
    task_success
}


function mpc_build() {

    task_start "Building libmpc ..."
    remove_build_folder "mpc"
    do_mkpushd ${builddir}/mpc

    CFLAGS="-fPIC" $(ls -d ${srcdir}/mpc-[0-9].[0-9]*)/configure \
        --build=${build_platform} \
        --host=${host_platform} \
        --disable-shared \
        --enable-static \
        --prefix=${PREFIX} \
        --with-mpfr=${PREFIX} \
        --with-gmp=${PREFIX} \
        > configure.out 2>&1 || task_error "configure failed. See configure.out."

    do_make  "Failed building libmpc. See make.out"
    task_success
    task_start "Installing mpc ..."
    do_make_install "make install failed. See make.install.out."
    do_popd
    task_success

}

function ncurses_prep() {
    task_start "Unpacking ncurses... "
    upstream_source=$(ls ${srcdir}/ncurses/ncurses*)
    unpack_upstream_source ${srcdir} ${upstream_source}
    task_success
}


function ncurses_build() {
    task_start "Building ncurses ..."
    remove_build_folder "ncurses"
    do_mkpushd ${builddir}/ncurses

    CFLAGS="-fPIC" $(ls -d ${srcdir}/ncurses-[0-9].*)/configure \
        --build=${build_platform} \
        --host=${host_platform} \
        --without-shared \
        --without-sysmouse \
        --without-progs \
        --enable-termcap \
        --prefix=${PREFIX} \
        > configure.out 2>&1 || task_error "configure failed. See configure.out."

    do_make  "Failed building ncurses. See make.out"
    task_success
    task_start "Installing ncurses ..."
    do_make_install "make install failed. See make.install.out."
    do_popd
    task_success
}

############# This is where the main part of the program starts ##
start_timer

############ Set up some usable variables #######################
SUDO_PASSWORD=
KEEP_BUILD_FOLDER="NO"
TIMESTAMP=$(date +%Y%m%d%H%M)
binutils_version_atmel="atmel-$(date +%Y%m%d%H%M%Z)"
gcc_version_atmel="atmel-$(date +%Y%m%d%H%M%Z)"
gdb_version_atmel="atmel-$(date +%Y%m%d%H%M%Z)"
platform_version=""
srcdir=
builddir=
execdir=`pwd`

# Set Toolchain version number
# Use env variable AVR_GNU_TOOLCHAIN_VERSION if set
avr_32_gnu_toolchain_version=${AVR_32_GNU_TOOLCHAIN_VERSION:-"3.2.0"}

# Set BUILD_NUMBER
# BUILD_NUMBER is set by Hudson build server or can be set before running this script
# If not set we use the date
BUILD_NUMBER=${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}

# Set defaults
canadian_cross=false
build_platform=$(uname -i)-pc-linux-gnu
host_platform=$(uname -i)-pc-linux-gnu
distribution="unknown"

# Set up the packages to build
# The order gives the build order and is significant
packages="avr32-binutils avr32-gcc-bootstrap avr32-newlib avr32-gcc-full"
linux_packages="avr32-linux-binutils avr32-linux-gcc-bootstrap avr32-uclibc \
                avr32-linux-gcc-full"


# See if we need to change or set some defaults
if test "${OSTYPE}" = "msys"
then
    build_platform=i686-pc-mingw32
    host_platform=i686-pc-mingw32
else
    distribution=`lsb_release -i |cut -f2` || echo "WARNING: Couldn't determine which distribution"
fi

############ Get and decode options given #########################
while getopts "B:b:klhH:p:P:s:T:" options; do
  case $options in
      B ) build_platform=$OPTARG
          ;;
      b )	builddir=$OPTARG
          ;;
      H ) host_platform=$OPTARG
          ;;
      k )
          KEEP_BUILD_FOLDER="YES"
          ;;
      l )
          echo "Default packages and build order:"
          for package in $packages
          do
              echo $package
          done
          echo "AVR32 Linux packages and build order (not default built):"
          for package in ${linux_packages}
          do
              echo $package
          done
          exit 1
          ;;
    p )	AVR32_PREFIX=$OPTARG
        ;;
    P ) SUDO_PASSWORD=$OPTARG
        ;;
      s )	srcdir=$OPTARG
          ;;
    h ) echo "$usage"
        exit 1;;
    \? ) echo "$usage"
         exit 1;;
    * ) echo "$usage"
          exit 1;;

  esac
done

shift $(($OPTIND - 1)) ## no need for expr in bash or other POSIX shell

######### Set packages to arguments given or to default ###########
if test $# -ne 0
then
    if test "$@" = "avr32-linux"
    then
        packages=${linux_packages}
    else
        packages="$@"
    fi
fi

############ Check for source directory ###########################
if test -z $srcdir
then
    echo "Using current directory as source folder."
    srcdir=$(pwd)
else
    echo "Using '${srcdir}' as source folder."
fi

if [ -d ${srcdir} ]
then
    # Convert path to absolute path
    srcdir=$(cd ${srcdir}; pwd)
else
    echo "Error: Can't find source folder!"
    exit 1
fi

############ Make the build dir ###################################
builddir="${builddir:-build}"
mkdir -p ${builddir} || task_error "Cannot create build folder"

# Get absolute path for builddir
builddir=$(cd ${builddir}; pwd)


######### Check for crosscompile ###############

# If build_platform != host_platform != target_platform
# the we are doing canadian cross
# since target always is avr32 or avr32-linx we check only
# the build and host platforms
if test ${host_platform} != ${build_platform}
then
    canadian_cross=true;
fi

# Set some platform variables
case "${host_platform}" in
    i[3456]86*-linux*)
        platform_version="\(linux32_special\)"
        ;;
    x86_64*-linux*)
        platform_version="\(linux64_special\)"
        ;;
    i[3456]86*-cygwin*)
        platform_version="\(cygwin_special\)"
        ;;
    i[3456789]86*-mingw32*)
        # Maybe check for some prerequisite?
        export CFLAGS="-D__USE_MINGW_ACCESS"
        platform_version="\(mingw32_special\)"
        ;;
    sparc*-sun-solaris2.[56789]*)
        ;;
    sparc*-sun-solaris*)
        ;;
    mips*-*-elf*)
        ;;
    * )
        echo "Unknown host platform: ${host_platform}"
        ;;
esac

############ Set PREFIX ############################
PREFIX="${AVR32_PREFIX:-/usr/local}"
# Make sure it is absolute path
PREFIX=$(cd ${PREFIX}; pwd)

PATH=$PATH:$PREFIX/bin

############# Check if user has write access to prefix folder ####
if test ! -w ${PREFIX} -a -z "${SUDO_PASSWORD}"
then
    echo "WARNING! You do not have write access to the $PREFIX folder! Installation will fail."
fi


############# Check for necessary programs #######################
for PREREQ in autoconf aclocal \
    automake autoheader \
    make gcc tar patch
do
    RUN=`type -ap $PREREQ |sort |uniq |wc -l`
    if [ $RUN -eq 0 ]
    then
        echo "$PREREQ is not found in command path. Can't continue"
        exit 1
    elif [ $RUN -gt 1 ]
    then
        echo -n "Found multiple versions of $PREREQ, using the one at "
        type -p $PREREQ
    fi
done


############# First we make necessary preparations ###############
for part in ${packages}
do
    case ${part} in
        "avr32-binutils" | "avr32-linux-binutils" )
            binutils_prep
            ;;
        "avr32-gcc-bootstrap" | "avr32-gcc-full" | "avr32-linux-gcc-bootstrap" | "avr32-linux-gcc-full" )
            gmp_prep
            mpfr_prep
            mpc_prep
            gcc_prep
            ;;
        "avr32-newlib" )
            newlib_prep
            ;;
        "avr32-gdb" | "avr32-linux-gdb" )
            ncurses_prep
            gdb_prep
            ;;
        "avr32-uclibc" )
            prep_kernel
            uclibc_prep
            ;;
        * )
            echo "Error: Unknown package ${part}."
            exit 1
            ;;
    esac
done


############# Now we can start building and installing ###########
# The order of building is given by the order in the packages variable
for part in ${packages}
do
    case ${part} in
        "avr32-binutils" )
            binutils_build "avr32"
            ;;
        "avr32-linux-binutils" )
            binutils_build "avr32-linux"
            ;;
        "avr32-gcc-bootstrap" )
            gmp_build
            mpfr_build
            mpc_build
            gcc_build_bootstrap "avr32"
            ;;
        "avr32-linux-gcc-bootstrap" )
            gcc_build_bootstrap "avr32-linux" "--disable-libgomp"
            ;;
        "avr32-gcc-full" )
            gmp_build
            mpfr_build
            mpc_build
            gcc_build_full "avr32" "--enable-__cxa_atexit --disable-shared --with-newlib"
            ;;
        "avr32-linux-gcc-full" )
            gcc_build_full "avr32-linux" "\
            --enable-__cxa_atexit \
            --enable-target-optspace \
            --enable-shared \
            --enable-threads \
            --disable-multilib \
            --enable-sjlj-exceptions \
            --disable-libmudflap"

            ;;
        "avr32-gdb" )
            case ${host_platform} in
                i68[3456]-*mingw32 )
                    ;;
                *linux* )
                    ncurses_build
                    ;;
                * )
                    ;;
            esac
            gdb_build "avr32"
            ;;
        "avr32-linux-gdb"	)
            gdb_build "avr32-linux"
            ;;
        "avr32-newlib" )
            newlib_build
            ;;
        "avr32-uclibc" )
            uclibc_build
            ;;
        * )
            echo "Error: Unknown package ${part}."
            exit 1
            ;;
    esac
done



end_timer
report_time
exit 0

##################################################################
# Now you should have a complete development enviroment for avr32
# installed at 'prefix' location.


