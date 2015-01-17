#!/bin/sh

# As of 1/2015 with latest Mavericks (10.9.5), Xcode (6.1.1), and macports, the
# following is needed to successfully build
# launchpad.net/gcc-arm-embedded (4.9-2014-q4)

INTENDED_FOR=gcc-arm-none-eabi-4_9-2014q4-20141203

# Set to native compiler that supports Ada
NATIVE_ADA=/opt/ada/gcc-4.9.2/bin

# This picks up macports
BUILDPATH=$NATIVE_ADA:/opt/local/bin:$PATH


if [ ! -f build-toolchain.sh ]
then
    echo "Must be run from within $INTENDED_FOR directory" 1>&2
    exit 1
fi

if [ $(basename $PWD) != $INTENDED_FOR ]
then
    echo "WARNING: Current directory does not appear to be what is expected" 1>&2
    echo "  Have:    " $(basename $PWD) 1>&2
    echo "  Expected: $INTENDED_FOR" 1>&2
    echo "  Continuing anyway..." 1>&2
fi

if [ $(uname) == "Darwin" ]
then
    CAFFEINATE=caffeinate
else
    CAFFEINATE=
fi

xpushd()
{
    pushd $@ >/dev/null
}

xpopd()
{
    popd >/dev/null
}

set -e
set -o pipefail

echo $(date) "started"

if [ ! -f build-common.sh.unpatched ]
then
    cp build-common.sh build-common.sh.unpatched
    # NOTE!  quotes around EOF are important!
    patch <<'EOF'
--- build-common.sh.unpatched	2015-01-13 13:14:49.000000000 -0600
+++ build-common.sh	2015-01-13 13:15:46.000000000 -0600
@@ -343,8 +343,9 @@
     HOST_NATIVE=x86_64-apple-darwin10
     READLINK=greadlink
 # Disable parallel build for mac as we will randomly run into "Permission denied" issue.
-#    JOBS=`sysctl -n hw.ncpu`
-    JOBS=1
+# jediunix - no, do parallel
+    JOBS=`sysctl -n hw.ncpu`
+#    JOBS=1
     GCC_CONFIG_OPTS_LCPP="--with-host-libstdcxx=-static-libgcc -Wl,-lstdc++ -lm"
     TAR=gnutar
     MD5="md5 -r"
EOF
else
    echo "build-common.sh already patched"
fi

if [ ! -f build-toolchain.sh.unpatched ]
then
    cp build-toolchain.sh build-toolchain.sh.unpatched
    # NOTE!  quotes around EOF are important!
    patch <<'EOF'
--- build-toolchain.sh.unpatched	2015-01-13 17:51:34.000000000 -0600
+++ build-toolchain.sh	2015-01-14 08:22:48.000000000 -0600
@@ -237,8 +237,10 @@
 saveenvvar CFLAGS "$ENV_CFLAGS"
 saveenvvar CPPFLAGS "$ENV_CPPFLAGS"
 saveenvvar LDFLAGS "$ENV_LDFLAGS"
+# jediunix added --disable-werror for sbrk in updated Mavericks/XCode
 $SRCDIR/$BINUTILS/configure  \
     ${BINUTILS_CONFIG_OPTS} \
+    --disable-werror \
     --target=$TARGET \
     --prefix=$INSTALLDIR_NATIVE \
     --infodir=$INSTALLDIR_NATIVE_DOC/info \
@@ -391,6 +393,7 @@
 rm -rf $BUILDDIR_NATIVE/gcc-final && mkdir -p $BUILDDIR_NATIVE/gcc-final
 pushd $BUILDDIR_NATIVE/gcc-final
 
+# jediunix - add Ada
 $SRCDIR/$GCC/configure --target=$TARGET \
     --prefix=$INSTALLDIR_NATIVE \
     --libexecdir=$INSTALLDIR_NATIVE/lib \
@@ -398,7 +401,8 @@
     --mandir=$INSTALLDIR_NATIVE_DOC/man \
     --htmldir=$INSTALLDIR_NATIVE_DOC/html \
     --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
-    --enable-languages=c,c++ \
+    --enable-languages=c,c++,ada \
+    --enable-cross-gnattools \
     --enable-plugins \
     --disable-decimal-float \
     --disable-libffi \
@@ -433,6 +437,11 @@
   make -j$JOBS INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
 fi
 
+# jediunix
+make -C gnattools gnattools
+rm gcc/stamp-tools
+make -C gcc cross-gnattools
+
 make install
 
 if [ "x$skip_manual" != "xyes" ]; then
@@ -504,7 +513,9 @@
 	saveenvvar CPPFLAGS "$ENV_CPPFLAGS"
 	saveenvvar LDFLAGS "$ENV_LDFLAGS"
 
+  # jediunix - add Ada
 	$SRCDIR/$GDB/configure  \
+	    --enable-languages=c,c++,ada \
 	    --target=$TARGET \
 	    --prefix=$INSTALLDIR_NATIVE \
 	    --infodir=$INSTALLDIR_NATIVE_DOC/info \
EOF
else
    echo "build-toolchain.sh already patched"
fi

xpushd src
for TAR in *.tar.*
do
    B=$(echo $TAR | sed 's:\.tar\..*::')
    if [ ! -d $B ]
    then
        echo "expanding src/$TAR ..."
        tar xjf $TAR
    else
        echo "src/$B already exists"
    fi
done
xpopd

xpushd src/gcc/gcc
if [ ! -f exec-tool.in.unpatched ]
then
    echo "in src/gcc/gcc ..."
    cp exec-tool.in exec-tool.in.unpatched
    patch <<'EOF'
--- exec-tool.in.unpatched	2014-10-06 01:27:22.000000000 -0500
+++ exec-tool.in	2015-01-13 13:20:21.000000000 -0600
@@ -33,9 +33,18 @@
 id=$invoked
 case "$invoked" in
   as)
+    #begin jediunix
+    if [ "$1" == "-arch" ]
+    then
+	original=/usr/bin/as
+    else
+    #end jediunix
     original=$ORIGINAL_AS_FOR_TARGET
     prog=as-new$exeext
     dir=gas
+    #begin jediunix
+    fi
+    #end jediunix
     ;;
   collect-ld)
     # Check -fuse-ld=bfd and -fuse-ld=gold
EOF
else
    echo "src/gcc/gcc/exec-tool.in already patched"
fi
xpopd

xpushd src/gcc/gnattools
if [ \! -f configure.unpatched -o \! -f configure.ac.unpatched ]
then
    echo "in src/gcc/gnattools ..."
    cp configure configure.unpatched
    cp configure.ac configure.ac.unpatched
# Patch from
# From f8c74c16b9f7ef3be02a9a7d3480baf88d09efd6 Mon Sep 17 00:00:00 2001
# From: "Luke A. Guest" <laguest@archeia.com>
# Date: Fri, 14 Feb 2014 13:53:27 +0000
# Subject: [PATCH 1/2] Set the target for a bare metal environment.
    patch <<'EOF'
--- configure.unpatched	2015-01-14 08:13:21.000000000 -0600
+++ configure	2015-01-14 08:13:21.000000000 -0600
@@ -2085,6 +2085,15 @@
     indepsw.adb<indepsw-mingw.adb"
     EXTRA_GNATTOOLS='../../gnatdll$(exeext)'
     ;;
+  # Any bare machine stuff can go here, i.e. mips-elf, arm-elf,
+  # arm-none-eabi-elf, etc.
+  #
+  # This file just enables the ability to build static libs with gnatmake and
+  # project files.
+  *-*-elf* | *-*-eabi*)
+    TOOLS_TARGET_PAIRS="\
+    mlib-tgt-specific.adb<mlib-tgt-specific-xi.adb"
+    ;;
 esac
 
 # From user or toplevel makefile.
--- configure.ac.unpatched	2015-01-14 08:13:21.000000000 -0600
+++ configure.ac	2015-01-14 08:13:21.000000000 -0600
@@ -125,6 +125,15 @@
     indepsw.adb<indepsw-mingw.adb"
     EXTRA_GNATTOOLS='../../gnatdll$(exeext)'
     ;;
+  # Any bare machine stuff can go here, i.e. mips-elf, arm-elf,
+  # arm-none-eabi-elf, etc.
+  #
+  # This file just enables the ability to build static libs with gnatmake and
+  # project files.
+  *-*-elf* | *-*-eabi*)
+    TOOLS_TARGET_PAIRS="\
+    mlib-tgt-specific.adb<mlib-tgt-specific-xi.adb"
+    ;;
 esac
 
 # From user or toplevel makefile.
EOF
else
    echo "src/gcc/gnattools/configure and src/gcc/gnattools/configure.ac already patched"
fi
xpopd

xpushd src/gcc
if [ \! -f configure.unpatched -o \! -f configure.ac.unpatched ]
then
    echo "in src/gcc ..."
    cp configure configure.unpatched
    cp configure.ac configure.ac.unpatched
# Patch from (eliminated unrelated changes)
# From a2b4516f93f4d99e5ddae4c1eed78f2014f0875b Mon Sep 17 00:00:00 2001
# From: "Luke A. Guest" <laguest@archeia.com>
# Date: Fri, 14 Feb 2014 13:54:29 +0000
# Subject: [PATCH 2/2] Added --enable-cross-gnattools flag for bare metal environment.
    patch <<'EOF'
--- configure.unpatched	2015-01-14 09:42:48.000000000 -0600
+++ configure	2015-01-14 09:51:09.000000000 -0600
@@ -749,6 +749,7 @@
 enable_libquadmath
 enable_libquadmath_support
 enable_libada
+enable_cross_gnattools
 enable_libssp
 enable_libstdcxx
 enable_static_libjava
@@ -1467,6 +1468,10 @@
   --disable-libquadmath-support
                           disable libquadmath support for Fortran
   --enable-libada         build libada directory
+  --enable-cross-gnattools
+                          Enable cross gnattools for cross-compiler for
+                          freestanding environment, --disable-libada is set
+                          automatically
   --enable-libssp         build libssp directory
   --disable-libstdcxx     do not build libstdc++-v3 directory
   --enable-static-libjava[=ARG]
@@ -3070,8 +3075,22 @@
   ENABLE_LIBADA=yes
 fi
 
-if test "${ENABLE_LIBADA}" != "yes" ; then
-  noconfigdirs="$noconfigdirs gnattools"
+# Check whether --enable-cross-gnattools was given.
+if test "${enable_cross_gnattools+set}" = set; then :
+  enableval=$enable_cross_gnattools; ENABLE_CROSS_GNATTOOLS=$enableval
+else
+  ENABLE_CROSS_GNATTOOLS=yes
+fi
+
+if test "${is_cross_compiler}" = "yes" && test "${ENABLE_CROSS_GNATTOOLS}" = "yes" ; then
+  if test "${target_vendor}" = "none" || test "${target_vendor}" = "unknown" ; then
+    enable_libada=no
+    ENABLE_LIBADA=$enable_libada
+  fi
+else
+  if test "${ENABLE_LIBADA}" != "yes" ; then
+    noconfigdirs="$noconfigdirs gnattools"
+  fi
 fi
 
 # Check whether --enable-libssp was given.
--- configure.ac.unpatched	2015-01-14 08:03:43.000000000 -0600
+++ configure.ac	2015-01-14 08:08:14.000000000 -0600
@@ -420,8 +420,21 @@
 [AS_HELP_STRING([--enable-libada], [build libada directory])],
 ENABLE_LIBADA=$enableval,
 ENABLE_LIBADA=yes)
-if test "${ENABLE_LIBADA}" != "yes" ; then
-  noconfigdirs="$noconfigdirs gnattools"
+
+AC_ARG_ENABLE(cross-gnattools,
+[AS_HELP_STRING([--enable-cross-gnattools], [Enable cross gnattools for cross-compiler for freestanding environment, --disable-libada is set automatically])],
+ENABLE_CROSS_GNATTOOLS=$enableval,
+ENABLE_CROSS_GNATTOOLS=yes)
+
+if test "${is_cross_compiler}" = "yes" && test "${ENABLE_CROSS_GNATTOOLS}" = "yes" ; then
+  if test "${target_vendor}" = "none" || test "${target_vendor}" = "unknown" ; then
+    enable_libada=no
+    ENABLE_LIBADA=$enable_libada
+  fi
+else
+  if test "${ENABLE_LIBADA}" != "yes" ; then
+    noconfigdirs="$noconfigdirs gnattools"
+  fi
 fi
 
 AC_ARG_ENABLE(libssp,
EOF
else
    echo "src/gcc/configure and src/gcc/configure.ac already patched"
fi
xpopd

set +e

echo $(date) "beginning build-prerequisites ... (log in build-prerequisites.log)"

$CAFFEINATE env -i "PATH=$BUILDPATH" ./build-prerequisites.sh >build-prerequisites.log 2>&1
if [ $? -ne 0 ]
then
    echo $(date) "build-prerequisites.sh FAILED" 1>&2
    echo "last 10 lines of log:" 1>&2
    tail -10 build-prerequisites.log 1>&2
    exit 1
fi

echo $(date) "beginning build-toolchain ... (log in build-toolchain.log)"

# manual and python in gdb not working with my macports
$CAFFEINATE env -i "PATH=$BUILDPATH" ./build-toolchain.sh --skip_steps=manual,gdb-with-python >build-toolchain.log 2>&1 
if [ $? -ne 0 ]
then
    echo $(date) "build-toolchain.sh FAILED" 1>&2
    echo "last 10 lines of log:" 1>&2
    tail -10 build-prerequisites.log 1>&2
    exit 1
fi

echo $(date) "done!"

echo "Ada RTS must be created manually"
