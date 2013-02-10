package perfSONAR_PS::LSCacheDaemon::LSCacheHandler;

use strict;
use warnings;

=head1 NAME

LSCacheHandler.pm - Downloads text files containing list of services 
registered in Lookup Service

=head1 DESCRIPTION

This daemon reads a hints file specified in a configuration file 
containing a list of URLs pointing to tarballs containing the list
of services. It finds the URL closest to it using ping and then 
downloads and expands the file. It does a conditional HTTP GET 
meaning it only downloads the files if they have been updated. 

=cut

our $VERSION = 3.3;

use Archive::Tar;
use Carp;
use File::Copy qw/move/;
use File::Copy::Recursive qw/dirmove/;
use File::Path qw/mkpath rmtree/;
use HTTP::Request;
use Log::Log4perl qw/get_logger/;
use LWP::UserAgent;
use Net::Ping;
use URI::URL;
use Date::Manip qw(UnixDate);
use perfSONAR_PS::Utils::ParameterValidation;

use constant HEARTBEAT_FILE => "ls_cache_heartbeat.txt";
use fields 'CONF', 'LOGGER', 'HINTS', 'INDEX_URLS', 'HTTP_ETAG', 
           'HTTP_LAST_MODIFIED', 'NEXT_UPDATE', 'LAST_URL', 
           'HEARTBEAT_HTTP_ETAG', 'HEARTBEAT_HTTP_LAST_MODIFIED';

=head2 new()

This call instantiates new objects. The object's "init" function must be called
before any interaction can occur.

=cut

sub new {
    my $class = shift;

    my $self = fields::new( $class );

    $self->{LOGGER} = get_logger( $class );
    
    return $self;
}

=head2 init()

This call initialize the fields. Must be called prior to interaction 
with module.

=cut
sub init {
    my ( $self, $conf ) = @_;
    
    $self->{CONF} = $conf;
    $self->{NEXT_UPDATE} = 0;
    $self->{HINTS} = {};
    $self->{INDEX_URLS} = ();
    $self->{HTTP_ETAG} = '';
    $self->{HTTP_LAST_MODIFIED} = '';
    $self->{HEARTBEAT_HTTP_ETAG} = '';
    $self->{HEARTBEAT_HTTP_LAST_MODIFIED} = '';
    $self->{LAST_URL} = '';
}

=head2 handle()

Find the closest download location, download tarball with conditional GET
and expand tarball

=cut
sub handle {
    my ( $self ) = @_;

    my $curr_time = time;
    if ($curr_time < $self->{NEXT_UPDATE}) {
        # Sleep until it's time to run again.
        sleep($self->{NEXT_UPDATE} - $curr_time);
    }

    if(time >= $self->{NEXT_UPDATE}){
        $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format( "org.perfSONAR.LSCacheDaemon.LSCacheHandler.handle.start"));
        #get hints file
        my $hints_response = $self->cond_get( 
            url => $self->{CONF}->{"hints_file"},
            etag =>$self->{HINTS}->{HTTP_ETAG},
            lastmod => $self->{HINTS}->{HTTP_LAST_MODIFIED});
        if($hints_response->{STATUS} eq 'NEW'){
            my @hints_urls = split "\n", $hints_response->{CONTENT};
            $self->{HINTS}->{HTTP_ETAG} = $hints_response->{HTTP_ETAG};
            $self->{HINTS}->{HTTP_LAST_MODIFIED} = $hints_response->{HTTP_LAST_MODIFIED};
            #sort by closest
            $self->{INDEX_URLS} = $self->find_closest_urls( urls => \@hints_urls);
        }
        
        #if no URLs then don't change anything and return
        if ((!$self->{INDEX_URLS}) || @{$self->{INDEX_URLS}} == 0) {
            $self->{NEXT_UPDATE} = time + $self->{CONF}->{'update_interval'};
            $self->{LOGGER}->error(perfSONAR_PS::Utils::NetLogger::format( 
                "org.perfSONAR.LSCacheDaemon.LSCacheHandler.handle.end",
                {
                    status => -1, 
                    msg => "No URLs obtained from hints file", 
                    next_update => $self->{NEXT_UPDATE} 
                }));
            return;
        }
    
        #get the data
        my $log_msg = "";
        foreach my $index_url(@{$self->{INDEX_URLS}}){
        
            #get heartbeat file
            my $heartbeat_url = $index_url;
            $heartbeat_url =~ s/(http.*\/).*/$1/;
            $heartbeat_url .= HEARTBEAT_FILE;
            $self->{LOGGER}->info("heartbeat_url=$heartbeat_url");
            #get tarball file        
            my $heartbeat_http_etag = '';
            my $heartbeat_http_last_mod = '';
            
            # check that the URL we're calling is the same as 
            # the one we have the etag and last-mod for
            if($self->{LAST_URL} =~ /^$index_url/){
                $heartbeat_http_etag = $self->{HEARTBEAT_HTTP_ETAG};
                $heartbeat_http_last_mod = $self->{HEARTBEAT_HTTP_LAST_MODIFIED};
            }
            my $heartbeat_response = $self->cond_get( 
                url => $heartbeat_url,
                etag => $heartbeat_http_etag,
                lastmod => $heartbeat_http_last_mod);
            
            if($heartbeat_response->{STATUS} eq 'NEW'){
                $self->{HEARTBEAT_HTTP_ETAG} = $heartbeat_response->{HTTP_ETAG};
                $self->{HEARTBEAT_HTTP_LAST_MODIFIED} = $heartbeat_response->{HTTP_LAST_MODIFIED}; 
            }elsif($heartbeat_response->{STATUS} eq 'ERROR'){
                $log_msg .= "Cannot determine freshness of cache at $index_url.";
                next;
            }
            
            #if new or not modified
            my $min_last_mod = time - $self->{CONF}->{'cache_freshness'};
            my $hb_last_mod = UnixDate($self->{HEARTBEAT_HTTP_LAST_MODIFIED}, "%s");
            if($min_last_mod > $hb_last_mod){
                #cache is stale so try next URL
                $log_msg .= "Cache was not fresh at $index_url.";
                next;
            }
                
            #get tar file        
            my $http_etag = '';
            my $http_last_mod = '';
            # check that the URL we're calling is the same as 
            # the one we have the etag and last-mod for
            if($self->{LAST_URL} eq $index_url){
                $http_etag = $self->{HTTP_ETAG};
                $http_last_mod = $self->{HTTP_LAST_MODIFIED};
            }
            my $index_response = $self->cond_get( 
                url => $index_url,
                etag => $http_etag,
                lastmod => $http_last_mod);
            
            if($index_response->{STATUS} eq 'ERROR'){
                next;
            }
            
            if($index_response->{STATUS} eq 'NEW'){
                eval{
                    #save tarball
                    open TAR, ">/tmp/cache.tgz" or croak 'Unable to write to /tmp/cache.tgz';
                    print TAR $index_response->{CONTENT};
                    close TAR;
                    
                    #unpack to temp location
                    rmtree '/tmp/pscache'; #don't throw error if doesn't exist
                    mkpath '/tmp/pscache' or croak("Cannot make directory /tmp/pscache");
                    my $tar = Archive::Tar->new('/tmp/cache.tgz',1);
                    $tar->setcwd( '/tmp/pscache' );
                    my @tar_files = $tar->list_files() or croak("Unable to read files: ".$tar->error);
                    my @files_to_extract = ();
                    foreach my $file (@tar_files) {
                        next if ($file eq '.' or $file eq '..');

                        push @files_to_extract, $file;
                    }

                    $tar->extract(@files_to_extract) or croak("Unable to extract files: ".$tar->error);

                    #copy tmp to perm dir
                    dirmove('/tmp/pscache', $self->{CONF}->{"cache_dir"}) or croak("Unable to move file to " . $self->{CONF}->{"cache_dir"});
                };
                if($@){
                    $self->{NEXT_UPDATE} = time + $self->{CONF}->{'update_interval'};
                    chomp $@;
                    $self->{LOGGER}->error(perfSONAR_PS::Utils::NetLogger::format( 
                        "org.perfSONAR.LSCacheDaemon.LSCacheHandler.handle.end",
                        {
                            status => -1,
                            msg => $@,
                            next_update => $self->{NEXT_UPDATE}
                        }));
                    return;
                }
                
                #archive the downloaded tarball
                $self->archive_file(orig_file => '/tmp/cache.tgz', new_local_name => 'cache.tgz');
                    
                # update HTTP headers
                $self->{LAST_URL} = $index_url;
                $self->{HTTP_ETAG} = $index_response->{HTTP_ETAG};
                $self->{HTTP_LAST_MODIFIED} = $index_response->{HTTP_LAST_MODIFIED};
            }
            last;
        }
        
        $self->{NEXT_UPDATE} = time + $self->{CONF}->{'update_interval'};
        $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format( 
            "org.perfSONAR.LSCacheDaemon.LSCacheHandler.handle.end",
            { next_update => $self->{NEXT_UPDATE}, msg => $log_msg }));
    }
}

=head2 cond_get()

Perform conditional GET to given URL with optional Etag and 
Last-Modified headers.

=cut
sub cond_get {
    my ( $self, @args ) = @_;
    my $params = validateParams( @args, { url => 1, etag => 0, lastmod => 0 } );
    my $result = {};
    $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format(
        "org.perfSONAR.LSCacheDaemon.LSCacheHandler.cond_get.start", 
        {url => $params->{url}}));
            
    my $ua = new LWP::UserAgent();
    $ua->agent("LSCacheClient-v1.0");
    
    my $http_request = HTTP::Request->new( GET => $params->{url} );
    if($params->{etag} && $params->{lastmod}){
        $http_request->header(
            If_None_Match => $params->{etag},
            If_Last_Modified => $params->{lastmod}
        );
    }
    
    my $http_response = $ua->request($http_request);
    if ($http_response->is_success) {
        $result->{STATUS} = "NEW";
        $result->{HTTP_ETAG} = $http_response->header('ETag');
        $result->{HTTP_LAST_MODIFIED} = $http_response->header('Last-Modified');
        $result->{CONTENT} = $http_response->content;
    }elsif($http_response->code eq '304' ) {
        $result->{STATUS} = "USECACHE";
    }else{
        $result->{STATUS} = "ERROR";
    }
    $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format(
        "org.perfSONAR.LSCacheDaemon.LSCacheHandler.cond_get.end", 
        { 
            http_response_code => $http_response->code,
            url => $params->{url}
        }));
    
    return $result;
}

=head2 find_closest_urls()

Sort URLs by shortest ping response time

=cut
sub find_closest_urls {
    my ( $self, @args ) = @_;
    my $params = validateParams( @args, { urls => 1 } );
    my %duration_map = ();
    my $ping = Net::Ping->new("external");
    $ping->hires();
    for my $url_string( @{ $params->{urls} }){
       my $url = new URI::URL $url_string;
       my ( $ret, $duration, $ip );
       eval{ 
            ( $ret, $duration, $ip ) = $ping->ping($url->host());
       };
       if($@){  
            $self->{LOGGER}->info("Error running ping: $@");
       }
       $duration_map{$url_string} = $duration if $duration;
    }
    my @sorted_urls = sort{ $duration_map{$a} <=> $duration_map{$b} } keys %duration_map;
    return \@sorted_urls;
}

=head2 archive_file()

Archive the file and rotate existing copies of same file

=cut
sub archive_file {
    my ( $self, @args ) = @_;
    my $params = validateParams( @args, { orig_file => 1, new_local_name => 1 } );
    $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.LSCacheDaemon.LSCacheHandler.archive_file.start"));
        
    #check if we want to archive
    if($self->{CONF}->{'archive_dir'} eq '' || $self->{CONF}->{'archive_count'} <= 0){
        return;
    }
    
    my $i = $self->{CONF}->{'archive_count'} - 1;
    my $filename = $self->{CONF}->{'archive_dir'} . '/' . $params->{'new_local_name'};
    eval {
        #delete last item in archive
        if($i > 0){
            unlink("$filename.$i");
        }else{
            unlink("$filename");
        }
        
        #rotate remaining files
        while($i > 0){
            if(-e "$filename.$i"){
                move ("$filename.$i", "$filename." . ($i + 1)) or croak "Unable to rotate $filename.$i";
            }
            $i--;
        }
        
        #move new file
        if(-e $filename){
            move($filename, "$filename.1") or croak "Unable to rotate $filename.1";
        }
        move($params->{orig_file}, $filename) or croak "Unable to create file $filename";
    };
    if($@){
        chomp $@;
        $self->{LOGGER}->error(perfSONAR_PS::Utils::NetLogger::format(
            "org.perfSONAR.LSCacheDaemon.LSCacheHandler.archive_file.end", 
            {
                status => -1, 
                msg => "Unable to archive file: " . $@
            }));
    }else{
        $self->{LOGGER}->info(perfSONAR_PS::Utils::NetLogger::format("org.perfSONAR.LSCacheDaemon.LSCacheHandler.archive_file.end"));
    }
}
__END__

=head1 SEE ALSO

L<Archive::Tar>, L<Carp>, L<File::Copy::Recursive>, 
L<File::Path>, L<HTTP::Request>, L<Log::Log4perl>, 
L<LWP::UserAgent>, L<Net::Ping>, L<URI::URL>,
L<perfSONAR_PS::Utils::ParameterValidation>

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: daemon.pl 3949 2010-03-12 18:04:21Z alake $

=head1 AUTHOR

Andy Lake, andy@es.net

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2010, Internet2

All rights reserved.

=cut
