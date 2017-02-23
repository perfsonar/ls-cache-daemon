#!/bin/bash
# Usage info
show_help() {
    cat << EOF
        Usage: ${0##*/} [-a]  [- commit_options] [-n] [-t tag_options] [-v]
        This script releases a new version (final or RC) of a perfSONAR Debian package.
        It looks for the version of the package in the debian/changelog file. It creates a
        new git commit with all files ready to be commited and add the corresponding tag.
        The file debian/changelog is automatically modified by this script and added to the
        git commit.

        Two environment variables can be used to generate the changelog:
            - DEBEMAIL: the email mentioned in the changelog signature
            - DEBFULLNAME: the name mentioned in the changelog signature
        If those 2 variables are not defined, then your git user.email and user.name will
        be used instead.

        You can call it with the following args:
            -a: add modified files to the commit (use `git commit -a`)
            -c: additional git options to be passed to `git commit`
            -m: releases a minor package
            -n: performs a dry-run
            -t: additional git options to be passed to `git tag`
            -v: verbose
EOF
}

# Error handler
error() {
    echo -e "\033[1m$1\033[0m" >&2
    echo -e "\033[1;31mBetter I stop now, before doing any commit to the local repo.\033[0m" >&2
    exit 1
}

# Verbose handler
verbose() {
    [ $v -eq 0 ] || echo -e $1
}

# Defaults
v=0
dry_run=0
minor_pkg=0

# Parsing options
while getopts "ac:mnt:v" OPT; do
    case $OPT in
        a) commit_a="-a" ;;
        c) commit_options=$OPTARG ;;
        m) minor_pkg=1 ;;
        n) dry_run=1 ;;
        t) tag_options=$OPTARG ;;
        v) 
            v=1
            verbose "\033[1mI'm running in verbose mode.\033[0m" ;;
        '?')
            show_help >&2
            exit 1 ;;
    esac
done
shift $((OPTIND-1))

# Some sanity checks
if [[ -f debian/changelog && -f debian/gbp.conf ]]; then
    verbose "debian/changelog and debian/gbp.conf are present, that's a good start."
else
    error "This doesn't look like a Debian packaging tree, I cannot find debian/changelog or debian/gbp.conf."
fi

# Check Debian branch
BRANCH=`git branch --list | awk '/^\* .*$/ {print $2}'`
DEBIAN_BRANCH=`awk -F '=' '/debian-branch/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' debian/gbp.conf`
if [ "$BRANCH" = "$DEBIAN_BRANCH" ]; then
    verbose "Current git branch ($BRANCH) matches the gbp configured branch ($DEBIAN_BRANCH)."
else
    error "Your current git branch ($BRANCH) is not the same as the branch configured for gbp ($DEBIAN_BRANCH)."
fi

# Get some package information from the repo
PKG=`awk 'NR==1 {print $1}' debian/changelog`
PKG_VERSION=`awk 'NR==1 {gsub(/^\(|\)$/, "", $2); print $2}' debian/changelog`
CH_DISTRO=`awk 'NR==1 {gsub(/;$/, "", $3); print $3}' debian/changelog`
BUILD_DISTRO=`awk -F 'DIST=' '/builder/ {gsub(/[ \t]+.*$/, "", $2); print $2}' debian/gbp.conf`

# The versions and tags need to conform to our policy detailed at https://github.com/perfsonar/project/wiki/Versioning
if grep -q '(native)' debian/source/format ; then
    # Native package don't have release numbers, only a version number
    VERSION=${PKG_VERSION}
    # We don't have an upstream version either
    UPSTREAM_VERSION=${VERSION}
    TAG_VERSION=${PKG_VERSION/\~bpo/_bpo}
    TAG_VERSION=${TAG_VERSION//\~/-}
    if [ "${minor_pkg}" -eq 1 ]; then
        DEBIAN_TAG="debian/${BUILD_DISTRO}/${PKG}-${TAG_VERSION}"
    else
        DEBIAN_TAG="debian/${BUILD_DISTRO}/${TAG_VERSION}"
    fi
else
    VERSION=${PKG_VERSION%-*}
    PKG_REL="-${PKG_VERSION##*-}"
    UPSTREAM_VERSION=${VERSION/\~/-}
    if [ "${minor_pkg}" -eq 1 ]; then
        DEBIAN_TAG="debian/${BUILD_DISTRO}/${PKG}-${UPSTREAM_VERSION}${PKG_REL//\~/_}"
    else
        DEBIAN_TAG="debian/${BUILD_DISTRO}/${UPSTREAM_VERSION}${PKG_REL//\~/_}"
        # Check there is a corresponding upstream tag
        git tag -l | grep -q $UPSTREAM_VERSION
        if [ $? -ne 0 ]; then
            error "$PKG_VERSION of $PKG doesn't seem to have a corresponding upstream tag."
        fi
    fi
fi

# Check there is not an already existing Debian tag
git tag -l | grep -q $DEBIAN_TAG
if [ $? -eq 0 ]; then
    error "$DEBIAN_TAG is already existing in this repository."
fi

# Check distro field in debian/changelog
if [ "$VERSION" = "$UPSTREAM_VERSION" ]; then
    if ! grep -q '(native)' debian/source/format ; then
        verbose "We have a final release! Celebrate for $PKG_VERSION coming from upstream $UPSTREAM_VERSION"
    else
        verbose "We have a final release! Celebrate for $PKG_VERSION (native package)."
    fi
    REL="release"
else
    if ! grep -q '(native)' debian/source/format ; then
        verbose "We have an alpha, beta or candidate release: $PKG_VERSION coming from upstream $UPSTREAM_VERSION"
    else
        verbose "We have an alpha, beta or candidate release: $PKG_VERSION (native package)."
    fi
    REL="staging"
fi
PS_DEB_REP="perfsonar-${BUILD_DISTRO}-${REL}"
# We can have UNRELEASED as distro (we will change it later on), or it must be the correct $PS_DEB_REP
if [[ "$CH_DISTRO" = "UNRELEASED" || "$CH_DISTRO" = "$PS_DEB_REP" ]]; then
    verbose "The distribution filed in the debian/changelog file looks good: $CH_DISTRO."
else
    error "The distribution field in the debian/changelog file should be: $PS_DEB_REP (or UNRELEASED)"
fi

# Replace debian/changelog signature line with commiter or DEBIAN_EMAIL info
if [ -z "$DEBEMAIL" ]; then
    DEBEMAIL=`git config user.email`
    DEBFULLNAME=`git config user.name`
fi
# We use a date format that is working on both Linux and BSD
DATE=`LANG=C date "+%a, %d %b %Y %T %z"`
FINISH_LINE=" -- ${DEBFULLNAME} <${DEBEMAIL}>  ${DATE}"
verbose "The package signature line will be:"
[ $v -eq 0 ] || printf "${FINISH_LINE}\n"

# Make the git commit and tag
verbose "We're now going to release \033[1;32m${PKG}\033[0m at \033[1;32m${PKG_VERSION}\033[0m for \033[1;32m${PS_DEB_REP}\033[0m to the local git repo."
verbose "This release will be tagged as \033[1;32m${DEBIAN_TAG}\033[0m."
if [[ $dry_run -eq 1 ]]; then
    v=1
    verbose "\033[1mThis is a dry run, I haven't touch a thing.\033[0m"
    exit
fi
# Actually change the debian/changelog file
n=`grep -nm 1 " -- " debian/changelog | awk -F ':' '{print $1}'`
TMP_FILE=`mktemp`
sed "${n}s/^ -- .* [+-][0-9]\{4\}/${FINISH_LINE}/" debian/changelog > $TMP_FILE
sed "1s/ UNRELEASED;/ $PS_DEB_REP;/" $TMP_FILE > debian/changelog
/bin/rm $TMP_FILE
git add debian/changelog
# And perform the commit and the tagging
git commit ${commit_a} ${commit_options} -m "Releasing ${PKG} (${PKG_VERSION})"
git tag ${DEBIAN_TAG}

echo
echo "If you're happy with the commit and tag above, you just need to push them away!"
