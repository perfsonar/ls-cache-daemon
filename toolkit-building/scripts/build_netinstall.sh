#!/bin/bash

# Warning
if [ "$(id -u)" != 0 ]; then
	echo "Warning: SuperUser privileges required to use this script."
	read -p "Press [Enter] key to continue..."
fi

##############################
# Process Arguments
##############################
while [ $# -gt 0 ]; do
    case $1 in
		--arch)
			BUILD_ARCH=$2
			if [ -z $BUILD_ARCH ]; then
				echo "No architecture specified, exiting..."
				exit 1
			fi
			if [ ! $BUILD_ARCH = "i386" -a ! $BUILD_ARCH = "x86_64" ]; then
				echo "Invalid architecture specified, exiting..."
				exit 1
			fi
			shift
			shift
			;;
		--iso)
			ISO=$2
			if [ -z $ISO ]; then
				echo "No ISO file specified, exiting..."
				exit 1
			fi
			shift
			shift
			;;
		--os-version)
			BUILD_OS_VERSION=$2
			if [ -z $BUILD_OS_VERSION ]; then
				echo "No OS version specified, exiting..."
				exit 1
			fi
			shift
			shift
			;;
		--ps-version)
			BUILD_VERSION=$2
			if [ -z $BUILD_VERSION ]; then
				echo "No PS version specified, exiting..."
				exit 1
			fi
			shift
			shift
			;;
		-*)
			echo "Invalid arg: $1"
			exit 1
			;;
		*)
			break
			;;
    esac
done

####################################
# Configuration that often changes
####################################
BUILD_VERSION="${BUILD_VERSION:-3.5.1}" #perfSONAR version
BUILD_OS_VERSION="${BUILD_OS_VERSION:-6.8}" #CentOS version
BUILD_OS_VERSION_MAJOR=${BUILD_OS_VERSION%.*}

##############################
# Build Configuration
##############################
ISO_DOWNLOAD_SERVER="linux.mirrors.es.net"
BUILD=pS-Toolkit
BUILD_SHORT=pS-Toolkit
BUILD_DATE=`date "+%Y-%m-%d"`
BUILD_ID=`date +"%Y%b%d"`
BUILD_OS="CentOS$BUILD_OS_VERSION_MAJOR"
BUILD_OS_NAME="CentOS"
BUILD_TYPE=NetInstall
if [ -z $BUILD_ARCH ]; then
	BUILD_ARCH=x86_64
fi

BUILD_OS_LOWER=`echo $BUILD_OS | tr '[:upper:]' '[:lower:]'`
BUILD_OS_NAME_LOWER=`echo $BUILD_OS_NAME | tr '[:upper:]' '[:lower:]'`
BUILD_TYPE_LOWER=`echo $BUILD_TYPE | tr '[:upper:]' '[:lower:]'`
# Assume we're running from the 'scripts' directory
SCRIPTS_DIRECTORY=`dirname $(readlink -f $0)`
mkdir -p $SCRIPTS_DIRECTORY/../resources
if [ -z "$ISO" ]; then
	ISO=$(ls $SCRIPTS_DIRECTORY/../resources/$BUILD_OS_NAME-$BUILD_OS_VERSION-$BUILD_ARCH-$BUILD_TYPE*.iso $SCRIPTS_DIRECTORY/../resources/$BUILD_OS_NAME-$BUILD_OS_VERSION-$BUILD_ARCH-$BUILD_TYPE_LOWER*.iso 2>/dev/null)
	if [ ! -e "$ISO" ]; then
	    pushd $SCRIPTS_DIRECTORY/../resources
	    wget "http://$ISO_DOWNLOAD_SERVER/$BUILD_OS_NAME_LOWER/$BUILD_OS_VERSION/isos/$BUILD_ARCH/" \
	        -r -np -nd -erobots=off -A "*$BUILD_TYPE*.iso" -A "*$BUILD_TYPE_LOWER*.iso"
	    popd
	fi
	ISO=$(ls $SCRIPTS_DIRECTORY/../resources/$BUILD_OS_NAME-$BUILD_OS_VERSION-$BUILD_ARCH-$BUILD_TYPE*.iso $SCRIPTS_DIRECTORY/../resources/$BUILD_OS_NAME-$BUILD_OS_VERSION-$BUILD_ARCH-$BUILD_TYPE_LOWER*.iso 2>/dev/null)
fi

##############################
# Kickstart Configuration
##############################
KICKSTARTS_DIRECTORY=$SCRIPTS_DIRECTORY/../kickstarts
KICKSTART_FILE=$BUILD_OS_LOWER-$BUILD_TYPE_LOWER.cfg
PATCHED_KICKSTART=`mktemp`

##############################
# ISO Configuration
##############################
ISO_MOUNT_POINT=/mnt/iso
OUTPUT_ISO=$BUILD-$BUILD_VERSION-$BUILD_OS-$BUILD_TYPE-$BUILD_ARCH-$BUILD_ID.iso
OUTPUT_MD5=$OUTPUT_ISO.md5
LOGO_FILE=$SCRIPTS_DIRECTORY/../images/$BUILD-Splash-$BUILD_VERSION.gif

# Caches
CACHE_DIRECTORY=/var/cache/live

##############################
# Apply Patch
##############################
echo "Patching $KICKSTART_FILE."
pushd $KICKSTARTS_DIRECTORY > /dev/null 2>&1

# Set correct build architechture
cp $KICKSTART_FILE $PATCHED_KICKSTART
sed -i "s/\[BUILD_ARCH\]/$BUILD_ARCH/g" $PATCHED_KICKSTART
popd > /dev/null 2>&1

##############################
# Create Extra Loop Devices
##############################
echo "Creating extra loop devices."
MAX_LOOPS=256
NUM_LOOPS=$((`/sbin/losetup -a | wc -l` + 8))
NUM_LOOPS=$(($NUM_LOOPS + (16 - $NUM_LOOPS % 16)))
if [ $NUM_LOOPS -gt $MAX_LOOPS ]; then
	echo "Couldn't find enough unused loop devices."
	exit -1
fi
if [ -x /sbin/MAKEDEV ]; then
	/sbin/MAKEDEV -m $NUM_LOOPS loop
fi

##############################
# Create Mount Point and Mount ISO
##############################
pushd $SCRIPTS_DIRECTORY/../resources > /dev/null 2>&1
echo "Creating mount point for ISO: $ISO_MOUNT_POINT."
mkdir -p $ISO_MOUNT_POINT
if [ $? != 0 ]; then
	echo "Couldn't create mount point: $ISO_MOUNT_POINT."
	exit -1
fi

echo "Mounting ISO file."
mount -t iso9660 -o loop $ISO $ISO_MOUNT_POINT
if [ $? != 0 ]; then
	echo "Couldn't mount $ISO at $ISO_MOUNT_POINT."
	exit -1
fi

##############################
# Create Temporary Directory and Build NetInstall
##############################
echo "Creating temporary directory."
TEMP_DIRECTORY=`mktemp -d`
if [ ! -d $TEMP_DIRECTORY ]; then
	echo "Couldn't create temporary directory."
	exit -1
fi

echo "Building $BUILD_TYPE in $TEMP_DIRECTORY."
rm -rf $TEMP_DIRECTORY
cp -Ra $ISO_MOUNT_POINT $TEMP_DIRECTORY

mv $PATCHED_KICKSTART $TEMP_DIRECTORY/isolinux/$BUILD_OS_LOWER-$BUILD_TYPE_LOWER.cfg

echo "Placing kickstart into initrd.img"
pushd $TEMP_DIRECTORY/isolinux
if file initrd.img | grep -q LZMA; then
    XZ_OPTS="--format=lzma"
else
    XZ_OPTS="--format=xz --check=crc32"
fi
mv initrd.img initrd.img.xz
xz $XZ_OPTS initrd.img.xz --decompress
echo $BUILD_OS_LOWER-$BUILD_TYPE_LOWER.cfg | cpio -c -o -A -F initrd.img
xz $XZ_OPTS initrd.img --compress --stdout > initrd.img.xz
mv initrd.img.xz initrd.img
rm $BUILD_OS_LOWER-$BUILD_TYPE_LOWER.cfg
popd

##############################
# Update isolinux Configuration and Create Boot Logo
##############################
echo "Updating isolinux configuration."
cat > $TEMP_DIRECTORY/isolinux/boot.msg <<EOF
17splash.lss
perfSONAR Toolkit    Integrated by the perfSONAR Team  Build Date:
http://www.perfsonar.net  Hit enter to continue    $BUILD_DATE
EOF

sed -e "s/\\[BUILD_VERSION\\]/$BUILD_VERSION/" \
    -e "s/\\[KS_FILE\\]/$BUILD_OS_LOWER-$BUILD_TYPE_LOWER.cfg/" \
    $SCRIPTS_DIRECTORY/../isolinux/centos$BUILD_OS_VERSION_MAJOR.cfg > $TEMP_DIRECTORY/isolinux/isolinux.cfg

if [ -f $LOGO_FILE ]; then
	echo "Building boot logo file."
	convert $LOGO_FILE ppm:- | ppmtolss16 '#FFFFFF=7' > $TEMP_DIRECTORY/isolinux/splash.lss
	convert -depth 16 -colors 65536 $LOGO_FILE $TEMP_DIRECTORY/isolinux/splash.png
	mv $TEMP_DIRECTORY/isolinux/splash.png $TEMP_DIRECTORY/isolinux/splash.jpg
fi

##############################
# Create new ISO and MD5 and Cleanup
##############################
echo "Generating new ISO: $OUTPUT_ISO"
mkisofs -r -R -J -T -v -no-emul-boot -boot-load-size 4 -boot-info-table -input-charset UTF-8 -V "$BUILD_SHORT" -p "$0" -A "$BUILD" -b isolinux/isolinux.bin -c isolinux/boot.cat -x “lost+found” -o $OUTPUT_ISO $TEMP_DIRECTORY
if [ $? != 0 ]; then
	echo "Couldn't generate $OUTPUT_ISO."
	exit -1
fi

# Make sure the ISO can boot on USB sticks
isohybrid $OUTPUT_ISO

echo "Implanting MD5 in ISO."
if [ -a /usr/bin/implantisomd5 ]; then
    /usr/bin/implantisomd5 $OUTPUT_ISO
elif [ -a /usr/lib/anaconda-runtime/implantisomd5 ]; then
    /usr/lib/anaconda-runtime/implantisomd5 $OUTPUT_ISO
else
    echo "Package isomd5 not installed."
fi

echo "Generating new MD5: $OUTPUT_MD5."
md5sum $OUTPUT_ISO > $OUTPUT_MD5

echo "Cleaning up $TEMP_DIRECTORY."
rm -rf $TEMP_DIRECTORY

echo "Unmounting temp ISO file."
umount -l $ISO_MOUNT_POINT
popd > /dev/null 2>&1

echo "$BUILD $BUILD_TYPE ISO created successfully."
echo "ISO file can be found in resources directory. Exiting..."
