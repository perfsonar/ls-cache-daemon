#!/bin/sh -x
# This script builds a perfSONAR Debian source package from a git repository checkout.
# It uses git-buildpackage and its configuration for the package in debian/gbp.conf
# It is made to work with Jenkins, for that purpose the git repository need to be checked out
# in a sub-directory of the Jenkins workspace, per convention we call this sub-directory 'source'.
# The resulting artefacts will be at the root level of the workspace.
#
# It also uses the following environment variables (or Jenkins parameters)
#   tag: the git tag to build from (ex: 4.0-2.rc1-1)
#   branch: the git branch to build from (ex: debian/jessie)
# If none of these variables/parameters are set, then the script looks for the branch to build
# in the debian/gbp.conf configuration file.

# Configuration
SRC_DIR='source'
GIT_BUILDING_REPO='toolkit-building'

# Trick to enable the Git parameter plugin to work with the source directory where we checked out
# the source code. Otherwise, the Git parameter plugin cannot find the tags existing in the repository
# This is a bug in the git-parameter plugin, see https://issues.jenkins-ci.org/browse/JENKINS-27726
ln -s ${SRC_DIR}/.git* .

# We don't want to package any submodule
cd ${SRC_DIR}
git submodule deinit -f .

# Kludge detection, this need to be done in the correct branch!
# This means that the Jenkins job must have "*/${branch}" as the Branch to be build.
if [ ! -f debian/gbp.conf ]; then
    # No debian directory, we're probably building pscheduler or a minor-package
    if [ -d "${package}" ]; then
        # It seems we're right, now, are we at the correct location?
        cd ${package}
        if ! [ -d debian ]; then
            cd */debian
            pscheduler_dir_level=".."
        else
            pscheduler_dir_level="."
        fi
        # We take the package name from the changelog entry, as this is not necessarily the same as the directory name...
        cd ${pscheduler_dir_level}
        package=`awk 'NR==1 {print $1}' debian/changelog`
    else
        echo
        echo "I don't recognise what you want me to build, pscheduler/minor-packages builds need to have the env variable 'package' set."
        echo "package=${package} and I don't see a directory with this name.  I stop."
        echo
        exit 1
    fi
fi

# Check the tag parameter, it has precedence over the branch parameter
DEBIAN_TAG=$tag
if [ -z $DEBIAN_TAG ]; then
    # If we don't have a tag parameter, let's look at the branch parameter
    if [ "${branch}" = "-" ]; then
        # No tag and no branch parameter, we look which branch we're building from
        DEBIAN_BRANCH=`awk -F '=' '/debian-branch/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' debian/gbp.conf`
    else
        DEBIAN_BRANCH=$branch
    fi
    if [ ! "${DEBIAN_BRANCH%%\/*}" = "debian" ]; then
        echo
        echo "This (${DEBIAN_BRANCH}) doesn't look like a Debian branch for me to build, I'll quit."
        echo
        exit 1
    fi
    export GIT_BRANCH=DEBIAN_BRANCH
    git checkout ${DEBIAN_BRANCH}
else
    # If we have a tag we check it out
    git checkout ${DEBIAN_TAG}
fi

# Get upstream branch from gbp.conf and making it a local branch so we can merge and build tarball from it
UPSTREAM_BRANCH=`awk -F '=' '/upstream-branch/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' debian/gbp.conf`
PKG=`awk 'NR==1 {print $1}' debian/changelog`
git branch ${UPSTREAM_BRANCH} origin/${UPSTREAM_BRANCH}

# Our default gbp options
GBP_OPTS="-nc --git-force-create --git-ignore-new --git-ignore-branch -S -us -uc --git-verbose --git-builder=/bin/true --git-cleaner=/bin/true --git-export-dir="

# Special repositories/packages needs
case "${PKG}" in
    "maddash")
        # MaDDash has a submodule we want to package!
        GBP_OPTS=$GBP_OPTS" --git-submodules"
        git submodule update --init maddash-server/madalert
        ;;
esac

# We differentiate snapshot and release builds
if [ -z $DEBIAN_TAG ]; then
    # If we don't have a tag, we take the source from the debian/branch and merge upstream in it so we have the latest changes
    echo "\nBuilding snapshot package of ${PKG} from ${DEBIAN_BRANCH}.\n"
    git merge --no-commit ${UPSTREAM_BRANCH}
    # We set the author of the Debian Changelog, only for snapshot builds (this doesn't seem to be used by gbp dch :(
    export DEBEMAIL="perfsonar-debian Autobuilder <debian@perfsonar.net>"
    # We can ignore NMU related warnings from LINTIAN as this package is not to be posted to official Debian repo
    LINTIAN_ARGS="--suppress-tags changelog-should-mention-nmu,source-nmu-has-incorrect-version-number"
    # And we generate the changelog ourselves, with a version number suitable for an upstream snapshot
    timestamp=`date +%Y%m%d%H%M%S`
    if [ "$pscheduler_dir_level" ]; then
        # pscheduler/minor-packages special
        if ! grep -q '(native)' debian/source/format ; then
            upstream_version=`dpkg-parsechangelog | sed -n 's/Version: \(.*\)-[^-]*$/\1/p'`
        else
            # For native packages, we take the full version string as upstream_version
            upstream_version=`dpkg-parsechangelog | sed -n 's/Version: \(.*\)$/\1/p'`
        fi
        if [ -e ../${package}_${upstream_version}.orig.tar.gz ] ||
            [ -e ../${package}_${upstream_version}.orig.tar.xz ] ||
            [ -e ../${package}_${upstream_version}.orig.tar.bz2 ]; then
            # We have the orig tarball in the repo, we only change the release number of the package.
            new_version=${upstream_version}-1+${timestamp}
        else
            new_version=${upstream_version}+${timestamp}-1
        fi
        dch -b --distribution=UNRELEASED --newversion=${new_version} -- 'SNAPSHOT autobuild for '${upstream_version}' via Jenkins'
    else
        gbp dch -S --ignore-branch -a
        sed -i "1 s/\((.*\)\(-[0-9]\{1,\}\)\(.*\))/\1+${timestamp}\3\2)/" debian/changelog
        GBP_OPTS="$GBP_OPTS --git-upstream-tree=branch --git-upstream-branch=${UPSTREAM_BRANCH}"
    fi
    dpkgsign="-k8968F5F6"
else
    # If we have a tag, we take the source from the git tag
    echo "\nBuilding release package of ${PKG} from ${DEBIAN_TAG}.\n"
    # We build the upstream tag from the Debian tag by, see https://github.com/perfsonar/project/wiki/Versioning :
    # - removing the leading debian/distro prefix
    # - removing the ending -1 debian-version field
    UPSTREAM_TAG=${DEBIAN_TAG##*\/}
    UPSTREAM_TAG=${UPSTREAM_TAG%-*}
    GBP_OPTS="$GBP_OPTS --git-upstream-tree=tag --git-upstream-tag=${UPSTREAM_TAG}"
    # We don't sign the release package as we don't have the packager's key
    dpkgsign="-us -uc"
fi

# We package the upstream sources (tarball) from git
if [ "$pscheduler_dir_level" ]; then
    # Directly calling git archive if pscheduler
    # Native package don't have upstream version, we don't need to create the upstream tarball
    if ! grep -q '(native)' debian/source/format ; then
        # We remove the -pkgrel suffix
        upstream_version=`dpkg-parsechangelog | sed -n 's/Version: \(.*\)-[^-]*$/\1/p'`
        if ! [ -e ../${package}_${upstream_version}.orig.tar.gz ] &&
            ! [ -e ../${package}_${upstream_version}.orig.tar.xz ] &&
            ! [ -e ../${package}_${upstream_version}.orig.tar.bz2 ]; then
            if [ -z $DEBIAN_TAG ]; then
                git archive -o ../${package}_${upstream_version}.orig.tar.gz ${UPSTREAM_BRANCH}
            else
                git archive -o ../${package}_${upstream_version}.orig.tar.gz ${UPSTREAM_TAG}
            fi
        fi
    fi
else
    # Or calling gbp for the other packages
    git-buildpackage $GBP_OPTS
fi
[ $? -eq 0 ] || exit 1

# Remove the GIT_BUILDING_REPO in case it re-emerged (with the --git-submodules option)
git submodule deinit -f ${GIT_BUILDING_REPO}

# Build the source package
dpkg-buildpackage ${dpkgsign} -nc -d -S -i -I --source-option=--unapply-patches
[ $? -eq 0 ] || exit 1
if [ "$pscheduler_dir_level" ]; then
    # With pscheduler repository structure, we must move the artefacts some levels up
    cd ..
    mv ${package}_* "${pscheduler_dir_level}/.."
    cd ${pscheduler_dir_level}
fi
echo "\nPackage source for ${PKG} is built.\n"

# Run Lintian on built package
cd ..
# Create lintian report in junit format, if jenkins-debian-glue is installed
if [ -x /usr/bin/lintian-junit-report ]; then
    /usr/bin/lintian-junit-report ${PKG}*.dsc > lintian.xml
else
    lintian ${LINTIAN_ARGS} --show-overrides ${PKG}*.dsc
fi

