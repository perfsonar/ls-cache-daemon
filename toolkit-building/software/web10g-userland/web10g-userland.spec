Name:           web10g-userland
Version:        2.0.4
Release:        1%{?dist}
Summary:        Web10g userland library and tools

Group:          System Environment/Libraries
License:        LGPL
URL:            http://www.web10g.org
Source0:        %{name}-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:	libmnl, libmnl-devel
Requires:	libmnl

%description
Web10G-userland provides a library and tools for the Web10G project; cf.

http://web10g.org

%package        utils
Summary:        Utilitied for %{name}
Group:          Development/Libraries
Requires:       %{name} = %{version}-%{release}

%description    utils
The %{name}-utils package contains various utilities for using or
testing %{name}.

%prep
%setup -q

%build
%configure
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make DESTDIR=%{buildroot} install

%clean
rm -rf %{buildroot}

%post -p /sbin/ldconfig

%postun -p /sbin/ldconfig

%files
%defattr(-,root,root,-)
%{_libdir}/libtcpe*
%{_includedir}/tcpe/*

%files utils
%{_bindir}/*

%changelog
* Wed Jan 23 2013 Aaron Brown <aaron@internet2.edu> - 2.0.4-1
- initial package build
