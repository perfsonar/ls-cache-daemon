%define py_ver         %(echo `python -c "import sys; print sys.version[:3]"`)
%define py_prefix      %(echo `python -c "import sys; print sys.prefix"`)
%define py_libdir      %{py_prefix}/lib/python%{py_ver}
%define py_incdir      /usr/include/python%{py_ver}
%define py_sitedir     %{py_libdir}/site-packages

%if ! (0%{?fedora} > 12 || 0%{?rhel} > 5)
%{!?python_sitelib: %global python_sitelib %(%{__python} -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")}
%{!?python_sitearch: %global python_sitearch %(%{__python} -c "from distutils.sysconfig import get_python_lib; print(get_python_lib(1))")}
%endif

Name:           web100_userland
Version:        1.7
Release:        7%{?dist}
Summary:        Web100 userland library and tools

Group:          System Environment/Libraries
License:        LGPL
URL:            http://www.web100.org
Source0:        %{name}-%{version}.tar.gz
Patch0:         web100_userland_ipv6_fix.patch
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:  python-devel, gtk2-devel
Requires:       python, gtk2


%define         __global_cflags -O2 -g -pipe -Wall


%description
The Web100 project provides the software and tools necessary for
end-hosts to automatically and transparently achieve high bandwidth data
rates (100 Mbps) over the high performance research networks.  This is
achieved through a combination of Linux kernel modifications and
userland tools.  This package includes a library, libweb100, and a set
of both graphical and command-line tools to achieve these goals.  The
kernel modifications are available separately.

%package        devel
Summary:        Development files for %{name}
Group:          Development/Libraries
Requires:       %{name} = %{version}-%{release}

%description    devel
The %{name}-devel package contains libraries and header files for
developing applications that use %{name}.


%prep
%setup -q
%patch0 -p0
perl -pi -e "s/WEB100_DOC_DIR=\\\${prefix}\/doc\/web100/WEB100_DOC_DIR=\\\${datadir}\/doc\/%{name}/" configure


%build

%configure --includedir=%{_includedir}
perl -pi -e "s/libweb100includedir = \\\$\(WEB100_INCLUDE_DIR\)\/web100/libweb100includedir = \\\$\(WEB100_INCLUDE_DIR\)/" lib/Makefile
%{__sed} -i -e 's|--install-platlib=${pyexecdir}|--install-platlib=${pyexecdir} --root=%{buildroot}|' python/Makefile



make %{?_smp_mflags}


%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot}
find %{buildroot} -name '*.la' -exec rm -f {} ';'


%clean
rm -rf %{buildroot}


%post -p /sbin/ldconfig

%postun -p /sbin/ldconfig


%files
%defattr(-,root,root,-)
%dir %{_docdir}/%{name}/
%doc %{_docdir}/%{name}/*-guide.txt
%{_bindir}/*
%{_libdir}/libweb100*
%{_includedir}/web100.h
%{_mandir}/man1
%{_mandir}/man3
%{_mandir}/man7
%{_datadir}/aclocal/web100.m4

%{_sysconfdir}/*.rc
%dir %{_datadir}/web100/
%{_datadir}/web100/*.gif
%{python_sitelib}/*
%{python_sitearch}/*

%changelog
* Thu Jul 14 2011 Derek Weitzel <dweitzel@cse.unl.edu> - 1.7-6
- Incorporate new python macros from fedora project
- Change included directory to python sitearch directory

* Thu Mar 02 2011 Aaron Brown <aaron@internet2.edu> - 1.7-5
- Include the official fix for the issue when ipv6 is enabled on the host

* Thu Jan 13 2011 Aaron Brown <aaron@internet2.edu> - 1.7-4
- Fix an issue when ipv6 is enabled on the host

* Wed Aug 26 2009 Tom Throckmorton <throck@mcnc.org> - 1.7-3
- incorporate python macro improvements from mgalgoci@redhat.com
- change cflags (again)

* Tue Oct 07 2008 Tom Throckmorton <throck@mcnc.org> - 1.7-2
- use new spec macros
- renabled python build
- add gtk requires, which enables gutil build
- override global_cflags, to prevent gutil from terminating

* Mon Jul 21 2008 Tom Throckmorton <throck@mcnc.org> - 1.7-1
- initial package build
