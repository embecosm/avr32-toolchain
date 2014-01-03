# AVR32 GNU Tool Chain

This is the main git repository for the Atmel AVR 32-bit GNU tool chain. It contains
just the scripts required to build the entire tool chain.

There are various branches of this repository which will automatically build
complete tool chains for various releases. This is the version for the
3.4.2 tool chain development branches.

When run, the build script will check out the appropriate branches for each of
the relevant tool chain component repositories.

## Prequisites

You will need a Linux like environment (Cygwin and MinGW environments under
Windows should work as well).

You will need the standard GNU tool chain pre-requisites as documented in
[GCC website](http://gcc.gnu.org/install/prerequisites.html)

Finally you will need to check out the repositories for each of the tool chain
components (its not all one big repository). These should be peers of this
toolchain directory. If you have yet to check any repository out, then the
following should be appropriate for creating a new directory, `avr` with all
the components.

    mkdir avr
    cd avr
    git clone git@github.com:embecosm/avr32-binutils-gdb.git binutils
    git clone git@github.com:embecosm/avr32-gcc.git gcc
    git clone git@github.com:embecosm/avr32-binutils-gdb.git gdb
    git clone git@github.com:embecosm/avr32-newlib.git newlib
    git clone git@github.com:embecosm/avr32-toolchain.git toolchain
    cd toolchain

__Note.__ The avr-binutils-gdb repository is cloned twice, to allow us
potentially to build tool chains with different versions of binutils and GDB.

For convenience, clone just the toolcahin repository, then run the script
[avr-clone-all.sh](https://github.com/embecosm/avr-toolchain/blob/avr-toolchain-mainline/avr-clone-all.sh)
in the toolchain directory, which will do the cloning for you:

    mkdir avr32
    cd avr32
    git clone git@github.com:embecosm/avr32-toolchain.git toolchain
    cd toolchain
    ./avr32-clone-all.sh

## Building the tool chain

The script `build-all.sh` will build and install AVR tool chains and AVR LibC. Use

    ./build-all.sh --help

to see the toptions available.

The script `avr32-versions.sh` specifies the branches to use in each component
git repository. It should be edited to change the default branches if
required.

Having checked out the correct branches and built a unified source directory,
`build-all.sh` first builds and installs the tool chain.

## Other information

The standard Atmel download is provided as patch files against the standard
GNU tool chain distributions. `SOURCES.README` describes these files,
`build-avr32-gnu-toolchain.sh` is the script to build from these sources. The
patch files themselves may be found in the patches directory.

The script `patchbuild.sh` is used to apply the patches as git commits,
creating appropriate ChangeLog.AVR32 entries. The git repository includes all
these commits.