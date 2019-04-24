#!/bin/bash

###
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###

#=========================================================================================================
# Program: build_ffmpeg.sh
#
# Ver         Date            Author          Comment
# =======     ===========     ===========     ==========================================
# V1.0.00     2018-12-27      DW              Build multimedia file converter 'FFmpeg' for SMS.
# V1.0.01     2019-04-23      DW              Specify to use Bourne shell explicitly to avoid compatibility
#                                             issue across different Linux/Unix systems. 
#=========================================================================================================

echo ""
echo "Build FFmpeg..."
echo ""

#-- Ensure required utilities have already installed --#
echo "check required utilities"
yum -y install bzip2.x86_64 > /tmp/build_ffmpeg.log

#-- Remember the FFmpeg stored 'home' --#
export FF_HOME=`pwd`
mkdir bin

#-- Check BUILD_PRELOAD variable --#
if [[ -v BUILD_PRELOAD ]]
then
  export BUILD_PRELOAD=$BUILD_PRELOAD
else
  export BUILD_PRELOAD=Y
fi  

#-- Step 1: Download FFmpeg source and required additional packages, and compile all additional packages. --#
echo ""
echo "================================================================="
echo "Download FFmpeg and required additional libraries, please wait..."
echo "================================================================="
echo ""
echo "Download FFmpeg"
curl -O https://ffmpeg.org/releases/ffmpeg-4.1.tar.bz2 >> /tmp/build_ffmpeg.log
bzip2 -d ffmpeg-4.1.tar.bz2 >> /tmp/build_ffmpeg.log
tar -xvf ffmpeg-4.1.tar >> /tmp/build_ffmpeg.log
mv -fv ./ffmpeg-4.1 ./ffmpeg >> /tmp/build_ffmpeg.log
rm -f ffmpeg-4.1.tar >> /tmp/build_ffmpeg.log

echo ""
echo "Download and compile libogg"
cd "$FF_HOME/ffmpeg"
curl -O https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.3.tar.gz >> /tmp/build_ffmpeg.log 
tar -xzvf libogg-1.3.3.tar.gz >> /tmp/build_ffmpeg.log
rm -f libogg-1.3.3.tar.gz >> /tmp/build_ffmpeg.log
cd libogg-1.3.3
./configure --prefix="$FF_HOME/ffmpeg" --disable-shared
make
make install
make distclean
cd "$FF_HOME"

echo ""
echo "Download and compile libvorbis"
cd "$FF_HOME/ffmpeg"
curl -O https://ftp.osuosl.org/pub/xiph/releases/vorbis/libvorbis-1.3.3.tar.gz >> /tmp/build_ffmpeg.log
tar -xzvf libvorbis-1.3.3.tar.gz >> /tmp/build_ffmpeg.log 
rm -f libvorbis-1.3.3.tar.gz >> /tmp/build_ffmpeg.log
cd libvorbis-1.3.3
./configure --prefix="$FF_HOME/ffmpeg" --with-ogg="$FF_HOME/ffmpeg" --disable-shared
make
make install
make distclean
cd "$FF_HOME" 

echo ""
echo "Download and compile opencore-amr"
cd "$FF_HOME/ffmpeg"
#-- Note: Since sourceforge use redirection for file download, so it must use this way to get this file. --#  
curl -L https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-0.1.5.tar.gz > opencore-amr-0.1.5.tar.gz
tar -xzvf opencore-amr-0.1.5.tar.gz >> /tmp/build_ffmpeg.log
rm -f opencore-amr-0.1.5.tar.gz >> /tmp/build_ffmpeg.log
cd opencore-amr-0.1.5
./configure --prefix="$FF_HOME/ffmpeg" --disable-shared --bindir="$FF_HOME/bin"
make
make install
make distclean
cd "$FF_HOME"

echo ""
echo "Download and compile yasm"
cd "$FF_HOME/ffmpeg"
curl -O http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz >> /tmp/build_ffmpeg.log
tar -xzvf yasm-1.3.0.tar.gz >> /tmp/build_ffmpeg.log
rm -f yasm-1.3.0.tar.gz >> /tmp/build_ffmpeg.log
cd yasm-1.3.0
./configure --prefix="$FF_HOME/ffmpeg" --bindir="/usr/bin"
make
make install
make distclean
cd "$FF_HOME"

#-- Step 2: Build FFmpeg --#
echo ""
echo "============================"
echo "Build FFmpeg, please wait..."
echo "============================"
echo ""
cd "$FF_HOME/ffmpeg"
mkdir -p "$FF_HOME/ffmpeg/tmp"
chmod 777 "$FF_HOME/ffmpeg/tmp"
export TMPDIR="$FF_HOME/ffmpeg/tmp"
export PKG_CONFIG_PATH="$FF_HOME/ffmpeg/lib/pkgconfig"
m=`ls -l /usr/bin/yasm | wc -l`
if (test $m = 0)
then  
  #-- If 'yasm' is missing, apply option '--disable-x86asm' to bypass using yasm to build FFmpeg. --#    
  ./configure --prefix="$FF_HOME/ffmpeg" --extra-cflags="-I$FF_HOME/ffmpeg/include" --extra-ldflags="-L$FF_HOME/ffmpeg/lib" --bindir="/usr/bin" --extra-libs="-ldl" --enable-gpl --enable-nonfree --enable-version3 --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libvorbis --disable-x86asm
else  
  ./configure --prefix="$FF_HOME/ffmpeg" --extra-cflags="-I$FF_HOME/ffmpeg/include" --extra-ldflags="-L$FF_HOME/ffmpeg/lib" --bindir="/usr/bin" --extra-libs="-ldl" --enable-gpl --enable-nonfree --enable-version3 --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libvorbis
fi  
make
make install
make distclean
rm -rfv $TMPDIR
export TMPDIR=""
export PKG_CONFIG_PATH=""

#-- Step 3: House keeping --#
cd "$FF_HOME"
rm -rf ffmpeg
rm -rf bin

#-- Step 4: Configure SMS system setting for audio converter --#
f=`ls -l /usr/bin/ffmpeg | wc -l`
if (test $f = 1)
then
  if (test $BUILD_PRELOAD = 'N')
  then  
    perl add_converter_setting.pl
  fi  
else
  echo ""
  echo "****************************************************************************************"
  echo "Audio converter FFmpeg built process is failure, please check for it after installation."
  echo "****************************************************************************************"
  echo ""
  read -p "Press enter to continue..."
  
  if (test $BUILD_PRELOAD = 'N')
  then
    perl ../remove_converter_setting.pl
  fi  
fi  

