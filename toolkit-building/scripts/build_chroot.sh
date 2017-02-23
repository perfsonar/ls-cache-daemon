#!/bin/bash

CHROOT_DIR=$1
ARCHITECTURE=$2
OS_VERSION=${3:-6}

if [ "$(id -u)" != 0 ]; then
	echo "Error: SuperUser privileges required to use this script."
	exit -1
fi

if [ -z "$CHROOT_DIR" ]; then
    echo "Need to specify the directory to use for building the chroot"
    exit -1
fi

if [ -z "$ARCHITECTURE" ]; then
    echo "Need to specify the architecture to use for building the chroot"
    exit -1
fi

#RPMS
CENTOS_REPO="http://mirror.centos.org/centos/$OS_VERSION/os/$ARCHITECTURE/Packages"
EPEL_REPO="http://download.fedoraproject.org/pub/epel/$OS_VERSION/$ARCHITECTURE"
I2_REPO="http://software.internet2.edu/rpms/el$OS_VERSION/$ARCHITECTURE/RPMS.main"

CENTOS_RELEASE_RPM=$(wget -q -O- $CENTOS_REPO | grep -o -P "centos-release-.*?rpm" | head -1)
EPEL_RELEASE_RPM=$(wget -q -O- $EPEL_REPO | grep -o -P "epel-release-.*?rpm" | head -1)
if [ -z "$EPEL_RELEASE_RPM" ]; then
    EPEL_REPO="$EPEL_REPO/e"
    EPEL_RELEASE_RPM=$(wget -q -O- $EPEL_REPO | grep -o -P "epel-release-.*?rpm" | head -1)
fi
I2_RPM=$(wget -q -O- $I2_REPO | grep -o -P "Internet2-repo-.*?rpm" | head -1)

mkdir -p $CHROOT_DIR
mkdir -p $CHROOT_DIR/var/lib/rpm
rpm --rebuilddb --root=$CHROOT_DIR

rpm -Uvh --nodeps --root=$CHROOT_DIR "$CENTOS_REPO/$CENTOS_RELEASE_RPM"

for gpg_key in $CHROOT_DIR/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-*$OS_VERSION; do
    if [ ! -e "/etc/pki/rpm-gpg/$(basename $gpg_key)" ]; then
        cp $gpg_key /etc/pki/rpm-gpg/
    fi
done

setarch $ARCHITECTURE yum --installroot=$CHROOT_DIR install -y rpm-build yum anaconda anaconda-runtime createrepo mkisofs
setarch $ARCHITECTURE yum --installroot=$CHROOT_DIR install -y "$EPEL_REPO/$EPEL_RELEASE_RPM" "$I2_REPO/$I2_RPM"

#make sure web100 is available
if [ "$OS_VERSION" -lt 7 ]; then
    sed -i -e 's|enabled.*=.*|enabled = 1|' $CHROOT_DIR/etc/yum.repos.d/Internet2-web100_kernel.repo
fi

# Mount the virtual file systems in the chroot so we can build things properly
mount --bind /proc $CHROOT_DIR/proc
mount --bind /dev $CHROOT_DIR/dev

# Allow us to resolve host names in the chroot jail
cp /etc/resolv.conf $CHROOT_DIR/etc/
