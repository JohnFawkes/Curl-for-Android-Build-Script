#!/bin/bash
echored () {
	echo "${TEXTRED}$1${TEXTRESET}"
}
echogreen () {
	echo "${TEXTGREEN}$1${TEXTRESET}"
}
usage () {
  echo " "
  echored "USAGE:"
  echogreen "ARCH=     (Default: all) (Valid Arch values: all, arm, arm64, aarch64, x86, i686, x64, x86_64)"
  echogreen "           Note that you can put as many of these as you want together as long as they're comma separated"
  echogreen "           Ex: ARCH=arm,x86"
  echo " "
  exit 1
}
OIFS=$IFS; IFS=\|; 
while true; do
  case "$1" in
    -h|--help) usage;;
    "") shift; break;;
    ARCH=*) eval $(echo "$1" | sed -e 's/=/="/' -e 's/$/"/' -e 's/,/ /g'); shift;;
    *) echo "Invalid option: $1!"; usage;;
  esac
done
IFS=$OIFS

TEXTRESET=$(tput sgr0)
TEXTGREEN=$(tput setaf 2)
TEXTRED=$(tput setaf 1)
DIR="`pwd`"
NDK=r19c
ZLVER="1.2.11"
OSVER="1.1.1c"
CRVER="7.65.2"
export OPATH=$PATH
export ANDROID_NDK_HOME=$DIR/android-ndk-$NDK
export ANDROID_TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin
export PATH=$ANDROID_TOOLCHAIN:$PATH

if [ -f /proc/cpuinfo ]; then
  JOBS=$(grep flags /proc/cpuinfo |wc -l)
elif [ ! -z $(which sysctl) ]; then
  JOBS=$(sysctl -n hw.ncpu)
else
  JOBS=2
fi

# Set up Android NDK
echogreen "Fetching Android NDK $NDK"
[ -f "android-ndk-$NDK-linux-x86_64.zip" ] || wget https://dl.google.com/android/repository/android-ndk-$NDK-linux-x86_64.zip
[ -d "android-ndk-$NDK" ] || unzip -o android-ndk-$NDK-linux-x86_64.zip

[ -z "$ARCH" -o "$ARCH" == "all" ] && ARCH="arm arm64 x86 x64"

for LARCH in $ARCH; do
  case $LARCH in
    arm64|aarch64) LARCH=aarch64; ARCHOS=android-arm64;;
    arm) LARCH=arm; ARCHOS=android-arm;;
    x64|x86_64) LARCH=x86_64; ARCHOS=android-x86_64;;
    x86) LARCH=i686; ARCHOS=android-x86;;
      *) echo "Invalid ARCH entered!"; usage;;
  esac

  export AR=$ANDROID_TOOLCHAIN/$LARCH-linux-android-ar
  export AS=$ANDROID_TOOLCHAIN/$LARCH-linux-android-as
  export LD=$ANDROID_TOOLCHAIN/$LARCH-linux-android-ld
  export CC=$ANDROID_TOOLCHAIN/$LARCH-linux-android21-clang
  export CXX=$ANDROID_TOOLCHAIN/$LARCH-linux-android21-clang++
  export RANLIB=$ANDROID_TOOLCHAIN/$LARCH-linux-android-ranlib
  export STRIP=$ANDROID_TOOLCHAIN/$LARCH-linux-android-strip

  # make symlink of clang to gcc
  if [ "$LARCH" == "arm" ]; then
    export AR=$ANDROID_TOOLCHAIN/$LARCH-linux-androideabi-ar
    export AS=$ANDROID_TOOLCHAIN/$LARCH-linux-androideabi-as
    export LD=$ANDROID_TOOLCHAIN/$LARCH-linux-androideabi-ld
    export RANLIB=$ANDROID_TOOLCHAIN/$LARCH-linux-androideabi-ranlib
    export STRIP=$ANDROID_TOOLCHAIN/$LARCH-linux-androideabi-strip
    export CC=$ANDROID_TOOLCHAIN/armv7a-linux-androideabi21-clang
    export CXX=$ANDROID_TOOLCHAIN/armv7a-linux-androideabi21-clang++
    ln -sf $CC `echo $CC | sed -e "s|armv7a|arm|" -e "s|21-clang|-gcc|"`
    ln -sf $CXX `echo $CXX | sed -e "s|armv7a|arm|" -e "s|21-clang|-gcc|"`
  else
    ln -sf $CC `echo $CC | sed "s|21-clang|-gcc|"`
    ln -sf $CXX `echo $CXX | sed "s|21-clang|-gcc|"`
  fi

  rm -rf $DIR/usr/lib $DIR/usr/include zlib-$ZLVER openssl-$OSVER curl-$CRVER
  mkdir -p $DIR/usr/lib $DIR/usr/include

  echogreen "Building Zlib..."
#  [ -f zlib-$ZLVER.tar.gz ] || wget http://zlib.net/zlib-$ZLVER.tar.gz
#  tar -xf zlib-$ZLVER.tar.gz
#  cd zlib-$ZLVER
  git clone https://github.com/madler/zlib.git -b develop
  cd zlib
  ./configure --static
  [ $? -eq 0 ] || continue
  make -j$JOBS
  [ $? -eq 0 ] || continue
  cp -f libz.a $DIR/usr/lib/libz.a
  cp -f zconf.h zlib.h $DIR/usr/include
  cd ..

  echogreen "Building Openssl..."
#  [ -f openssl-$OSVER.tar.gz ] || wget https://www.openssl.org/source/openssl-$OSVER.tar.gz
#  tar -xf openssl-$OSVER.tar.gz
#  cd openssl-$OSVER
  git clone https://github.com/openssl/openssl.git
  cd openssl
  ./Configure enable-md2 enable-rc5 enable-tls enable-tls1_3 enable-tls1_2 enable-tls1_1 no-shared "$ARCHOS" --with-zlib-include=$DIR/usr/include --with-zlib-lib=$DIR/usr/lib
  [ $? -eq 0 ] || continue
  make depend && make -j$JOBS
  [ $? -eq 0 ] || continue
  cp -f libcrypto.a libssl.a $DIR/usr/lib/
  cp -rf include/openssl $DIR/usr/include
  cd ..

  echogreen "Building cURL..."
#  [ -f curl-$CRVER.tar.gz ] || wget https://curl.haxx.se/download/curl-$CRVER.tar.gz
#  tar -xf curl-$CRVER.tar.gz
  git clone https://github.com/curl/curl.git
#  cd curl-$CRVER
  cd curl
  export CPPFLAGS="-I$DIR/usr/include"
  export LDFLAGS="-static -L$DIR/usr/lib"
  ./buildconf
   ./configure --enable-static --disable-shared --enable-cross-compile --with-ssl=$DIR/usr --with-zlib=$DIR/usr --host=$LARCH-linux-android --target=$LARCH-linux-android --disable-ldap --disable-ldaps --enable-ipv6 --enable-versioned-symbols --enable-threaded-resolver --without-ca-bundle --without-ca-path --with-ca-fallback
  [ $? -eq 0 ] || continue
  make curl_LDFLAGS=-all-static -j$JOBS
  [ $? -eq 0 ] || continue
  cp src/curl $DIR/curl-$LARCH
  $STRIP $DIR/curl-$LARCH
  echogreen "curl-$LARCH built successfully!"
done

echogreen "Building complete!"
exit 0
