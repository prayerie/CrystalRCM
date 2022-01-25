#!/usr/bin/env bash
cd "$(dirname "$0")"
LIBUSB="./assets/libusb.lib"
if [ ! -f $LIBUSB ]; then
    echo "libusb.lib not found!"
    echo "Please build the libusb dynamic library, rename it to libusb.lib, and place it in assets/"
else
    echo 'libusb.lib found!'
    echo 'Creating CrystalRCM.app with py2app...'
    python3 setup.py py2app > output.log 2>&1
    if [ $? -eq 0 ]; then
        echo 'dist/CrystalRCM.app created successfully.'
        echo 'Optimising size...'
        cd dist/CrystalRCM.app/Contents/
        rm Frameworks/libssl*
        rm Frameworks/libcrypto*
        rm Resources/lib/python3.10/lib-dynload/_codecs_*
        rm Resources/lib/python3.10/lib-dynload/unicodedata.so
        echo 'Done!'
    else
        echo 'py2app failed.'
        echo 'Please see output.log'
    fi

fi


