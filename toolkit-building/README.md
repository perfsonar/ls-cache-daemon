# perfSONAR Toolkit Building

This repository contains script to build the NetInstall and Full DVD ISOs of the Toolkit distribution.


##Building the NetInstall

The basic process is as follows:

```bash
./scripts/build_netinstall.sh --arch <i386|x86_64>
```

For more detailed instructions see https://github.com/perfsonar/project/wiki/CentOS-ISO-Build-Instructions#building-the-netinstall

##Building the Full DVD

The basic process is as follows:

```bash
./scripts/build_chroot.sh /path/to/chroot <i686|x86_64>
./scripts/build_full_dvd.sh --chroot /path/to/chroot --arch <i386|x86_64>
```

See https://github.com/perfsonar/project/wiki/CentOS-ISO-Build-Instructions

##Pre-releases (Alphas, Release Candidates, etc)
When preparing a pre-release, use the *pre-releases* branch. It is already setup to point at staging repositories. In some cases you may just need to change the version numbers in the following files:

* scripts/build_fulldvd.sh
* scripts/build_netinstall.sh

You should NEVER merge the pre-release branch into the master branch since it contains the staging repos, but you may want to do the reverse to ensure package lists and similar are in sync.


