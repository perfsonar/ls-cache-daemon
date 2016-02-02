%define install_base /usr/lib/perfsonar/
%define config_base  /etc/perfsonar

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-lscachedaemon

%define relnum 0.0.a1

Name:			perfsonar-lscachedaemon
Version:		3.5.1
Release:		%{relnum}
Summary:		perfSONAR Lookup Service Cache Daemon
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://www.perfsonar.net
Source0:		perfsonar-lscachedaemon-%{version}.%{relnum}.tar.gz
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
Requires:		perl(Log::Log4perl)
Requires:		perl(Log::Dispatch::FileRotate)
Requires:		perl(Net::DNS)
Requires:		perl(Net::Ping)
Requires:		perl(Net::Ping::External)
Requires:		perl(NetAddr::IP)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Regexp::Common)
Requires:		perl(Socket)
Requires:		perl(Time::HiRes)
Requires:		perl(URI::URL)
Requires:		perl(XML::LibXML)
Requires:		perl(base)
Requires:		chkconfig
Requires:		coreutils
Requires:		shadow-utils
Requires:		libperfsonar-perl
Obsoletes:		perl-perfSONAR_PS-LSCacheDaemon
Provides:		perl-perfSONAR_PS-LSCacheDaemon

%description
The perfSONAR LS Cache Daemon creates a cache of all services registered in
the LS by downloading a compressed file and expanding it to a configured
directory.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfsonar-lscachedaemon-%{version}.%{relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} CONFIGPATH=%{buildroot}/%{config_base} install

mkdir -p %{buildroot}/etc/init.d

install -D -m 0755 scripts/%{init_script_1} %{buildroot}/etc/init.d/%{init_script_1}
rm -rf %{buildroot}/%{install_base}/scripts/

%clean
rm -rf %{buildroot}

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/lscache
chown perfsonar:perfsonar /var/lib/perfsonar/lscache

#Update config file. For 3.5.1 will symlink to old location. In 3.6 we will move it.
if [ -L "%{config_base}/lscachedaemon.conf" ]; then
    echo "WARN: /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon.conf will be moved to %{config_base}/lscachedaemon.conf in 3.6. Update configuration management software as soon as possible. "
elif [ -e "/opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon.conf" ]; then
    mv %{config_base}/lscachedaemon.conf %{config_base}/lscachedaemon.conf.default
    ln -s /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon.conf %{config_base}/lscachedaemon.conf
    sed -i "s:/var/lib/perfsonar/ls_cache_daemon:/var/lib/perfsonar/lscachedaemon:g" /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon.conf
fi

#Update logging config file. For 3.5.1 will symlink to old location. In 3.6 we will move it.
if [ -L "%{config_base}/lscachedaemon-logger.conf" ]; then
    echo "WARN: /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon-logger.conf will be moved to %{config_base}/lscachedaemon-logger.conf in 3.6. Update configuration management software as soon as possible. "
elif [ -e "/opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon-logger.conf" ]; then
    mv %{config_base}/lscachedaemon-logger.conf %{config_base}/lscachedaemon-logger.conf.default
    ln -s /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon-logger.conf %{config_base}/lscachedaemon-logger.conf
    sed -i "s:ls_cache_daemon.log:lscachedaemon.log:g" /opt/perfsonar_ps/ls_cache_daemon/etc/ls_cache_daemon-logger.conf
fi

/sbin/chkconfig --add %{init_script_1}

%preun
if [ "$1" = "0" ]; then
	# Totally removing the service
	/etc/init.d/%{init_script_1} stop
	/sbin/chkconfig --del %{init_script_1}
fi

%postun
if [ "$1" != "0" ]; then
	# An RPM upgrade
	/etc/init.d/%{init_script_1} restart
fi

%files
%defattr(0644,perfsonar,perfsonar,0755)
%config %{config_base}/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) /etc/init.d/*
%{install_base}/lib/*

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
