#########################################################################################
# Name: yum_pkglist_from_ks.py
# Usage: python yum_pkglist_from_ks.py [options] kickstart outfile
# Description:
#  This script takes a kickstart file, extracts the package list, and finds all the 
#  dependencies in the dependency tree for those packages. This list is then output to a 
#  file with each package name on a line. The output file can be passed to a tool such as 
#  yum downloader to download all the packages needed for the kickstart. This can be 
#  especially useful when building custom Linux ISOs. 
########################################################################################

import yum
import optparse
import sys

################
# Setup CLI opts
################
parser = optparse.OptionParser(usage="python %prog [options] kickstart outfile")
parser.add_option('-i', '--installroot', dest="installroot", help="Install root for yum. Useful in chroot environments. Defaults to '/'.")
(options, args) = parser.parse_args()
if len(args) != 2:
    parser.print_help()
kickstart_path = args[0]
outfile = args[1]

###################
# Parse Kickstart
###################
kickstart = open(kickstart_path)
found_packages = False
input_pkg_names = []
input_pkg_groups = []
for line in kickstart:
    line = line.rstrip().lstrip()
    if not line:
        continue
    elif line.startswith("#"):
        continue
    elif line.startswith("%end"):
        break
    elif found_packages:
        if line.startswith("@"):
            input_pkg_groups.append(line.replace("@", ""))
        else:
            input_pkg_names.append(line)
    elif line.startswith("%packages"):
        found_packages = True
        
###################
# Initialize yum
###################
yb = yum.YumBase()
yb.conf.assumeyes = True
if options.installroot:
    yb.conf.installroot = options.installroot

############################
# Form initial package lists
############################
raw_pkg_names = {}
output_pkg_names = []
missing_pkg_names = []
pkg_names = input_pkg_names
##
# Expand package groups and add to inital package list
for input_pkg_group in input_pkg_groups:
    g = yb.comps.return_group(input_pkg_group)
    for p in g.packages:
        if p not in pkg_names:
            pkg_names.append(p)
            
############################
# Walk the dependency tree
############################
while pkg_names:
    pkj_objs = []
    while pkg_names:
        pkg_name = pkg_names.pop()
        ##
        # searchProvides allows us to look fo packages in lots of different forms
        # e.g perl(LWP) or perl-LWP
        results = yb.pkgSack.searchProvides(name=pkg_name)
        if not results:
            if pkg_name not in missing_pkg_names:
                ##
                # if we didn't find it, may not be a big deal. make sure we mark 
                # as visited though so we don't loop forever
                missing_pkg_names.append(pkg_name)
            continue
        for r in results:
            # use r.name to normalize package name to what yum actually calls it
            raw_pkg_names[r.name] = 1
        ##
        # Add pkg_name to list so we can also make we track searches we've already done 
        # where a specific package name was not given. e.g perl(LWP) vs perl-LWP
        output_pkg_names.append(pkg_name)
        pkj_objs.append(results[0])
    
    ##
    # For each package found go through the dependencies and find ones we haven't seen yet
    deps = yb.findDeps(pkj_objs)
    for parent_pkg in deps:
        for dep in deps[parent_pkg]:
            if (dep[0] not in output_pkg_names) and (dep[0] not in missing_pkg_names) and  (dep[0] not in pkg_names):
                pkg_names.append(dep[0])

################
# Output to file
################
fout = open(outfile, "w")
##
# Print out the package names as we saw them in kickstart and dependency list except for
# names like perl(LWP), libX.so, /usr/bin/python that yumdownloader won't take. This may
# be overkill and lead to some duplicates in the list, but ensures we get all we need
for r in output_pkg_names:
    if r.startswith("/"):
        continue
    elif "." in r:
        continue
    elif "(" in r:
        continue
    fout.write("%s\n" % r)
##
# Print the nicely formatted package names
for r in raw_pkg_names:
    fout.write("%s\n" % r)
fout.close()


    