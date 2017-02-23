Summary:    Datastax Yum Repository
Name:       datastax-repo
Version:    1.0
Release:    1
License:    distributable, see http://www.internet2.edu/membership/ip.html
Group:      System Environment/Base
URL:        http://www.datastax.com
Source0:    datastax-repo.tar.gz
BuildRoot:  %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:  noarch
Requires:   yum
Requires:   rpm

%description
Points at the datastax yum repo containing cassandra packages
%prep
%setup -q -n datastax-repo

%build

%install
%{__rm} -rf $RPM_BUILD_ROOT
%{__mkdir} -p $RPM_BUILD_ROOT/etc/yum.repos.d
%{__cp} datastax.repo $RPM_BUILD_ROOT/etc/yum.repos.d/datastax.repo

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root, 0644)
/etc/yum.repos.d/datastax.repo

%changelog
* Thu May 15 2014 Andy Lake <andy@es.net> - 1.0
- Adding rpm to easily setup datastax repo for perfSONAR Toolkit
