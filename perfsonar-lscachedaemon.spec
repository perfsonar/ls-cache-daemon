%define install_base /usr/lib/perfsonar/
%define config_base  /etc/perfsonar

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-lscachedaemon

%define perfsonar_auto_version 4.2.5
%define perfsonar_auto_relnum 0.a1.0

Name:			perfsonar-lscachedaemon
Version:		%{perfsonar_auto_version}
Release:		%{perfsonar_auto_relnum}%{?dist}
Summary:		perfSONAR Lookup Service Cache Daemon
License:		ASL 2.0
Group:			Development/Libraries
URL:			http://www.perfsonar.net
Source0:		perfsonar-lscachedaemon-%{version}.%{perfsonar_auto_relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch
Requires:		perl
Requires:		perl(Archive::Tar)
Requires:		perl(Config::General)
Requires:		perl(English)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Basename)
Requires:		perl(File::Copy)
Requires:		perl(File::Copy::Recursive)
Requires:		perl(File::Path)
Requires:		perl(Getopt::Long)
Requires:		perl(HTTP::Request)
Requires:		perl(IO::File)
Requires:		perl(IO::Socket)
Requires:		perl(IO::Socket::INET)
Requires:		perl(IO::Socket::INET6)
Requires:		perl(LWP::UserAgent)
Requires:		perl(LWP::Protocol::https)
Requires:		perl(Log::Log4perl)
Requires:		perl(Log::Dispatch::FileRotate)
Requires:		perl(Net::DNS)
Requires:		perl(Net::Ping)
Requires:		perl(NetAddr::IP)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Regexp::Common)
Requires:		perl(Socket)
Requires:		perl(Time::HiRes)
Requires:		perl(URI::URL)
Requires:		perl(XML::LibXML)
Requires:		perl(base)
Requires:		coreutils
Requires:		shadow-utils
Requires:		libperfsonar-perl
Obsoletes:		perl-perfSONAR_PS-LSCacheDaemon
Provides:		perl-perfSONAR_PS-LSCacheDaemon
%if 0%{?el7}
BuildRequires: systemd
%{?systemd_requires: %systemd_requires}
%else
Requires:               chkconfig
%endif

%description
The perfSONAR LS Cache Daemon creates a cache of all services registered in
the LS by downloading a compressed file and expanding it to a configured
directory.

%pre
/usr/sbin/groupadd -r perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfsonar-lscachedaemon-%{version}.%{perfsonar_auto_relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} CONFIGPATH=%{buildroot}/%{config_base} install

%if 0%{?el7}
install -D -m 0644 scripts/%{init_script_1}.service %{buildroot}/%{_unitdir}/%{init_script_1}.service
%else
install -D -m 0755 scripts/%{init_script_1} %{buildroot}/etc/init.d/%{init_script_1}
%endif

rm -rf %{buildroot}/%{install_base}/scripts/

%clean
rm -rf %{buildroot}

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/lscache
chown perfsonar:perfsonar /var/lib/perfsonar/lscache

%if 0%{?el7}
%systemd_post %{init_script_1}.service
if [ "$1" = "1" ]; then
    #if new install, then enable
    systemctl enable %{init_script_1}.service
    systemctl start %{init_script_1}.service
fi
%else
if [ "$1" = "1" ]; then
    # clean install, check for pre 3.5.1 files
    if [ -e "/opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon.conf" ]; then
        mv %{config_base}/lscachedaemon.conf %{config_base}/lscachedaemon.conf.default
        mv /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon.conf %{config_base}/lscachedaemon.conf
        sed -i "s:/var/lib/perfsonar/ls_cache:/var/lib/perfsonar/lscache:g" %{config_base}/lscachedaemon.conf
    fi
    
    if [ -e "/opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon-logger.conf" ]; then
        mv %{config_base}/lscachedaemon-logger.conf %{config_base}/lscachedaemon-logger.conf.default
        mv /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon-logger.conf %{config_base}/lscachedaemon-logger.conf
        sed -i "s:ls_cache_daemon.log:lscachedaemon.log:g" %{config_base}/lscachedaemon-logger.conf
    fi
fi

/sbin/chkconfig --add %{init_script_1}
%endif

%preun
%if 0%{?el7}
%systemd_preun %{init_script_1}.service
%else
if [ "$1" = "0" ]; then
	# Totally removing the service
	/etc/init.d/%{init_script_1} stop
	/sbin/chkconfig --del %{init_script_1}
fi
%endif

%postun
%if 0%{?el7}
%systemd_postun_with_restart %{init_script_1}.service
%else
if [ "$1" != "0" ]; then
	# An RPM upgrade
	/etc/init.d/%{init_script_1} restart
fi
%endif

%files
%defattr(0644,perfsonar,perfsonar,0755)
%license LICENSE
%config %{config_base}/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%{install_base}/lib/*
%if 0%{?el7}
%attr(0644,root,root) %{_unitdir}/%{init_script_1}.service
%else
%attr(0755,perfsonar,perfsonar) /etc/init.d/*
%endif

%changelog
* Thu Jun 19 2014 andy@es.net 3.4-1
- Updated links to new source repo

* Fri Jan 11 2013 asides@es.net 3.3-1
- 3.3 beta release

* Thu Sep 27 2010 aaron@internet2.edu 3.1-7
- Bugfix for extracting tarballs with '.' and '..' in them

* Thu Sep 07 2010 aaron@internet2.edu 3.1-6
- Get cache daemon to work with an older version of Archive::Tar

* Thu Mar 30 2010 andy@es.net 3.1-5
- Initial spec file created
