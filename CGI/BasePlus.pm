package CGI::BasePlus;

require 5.001;
use CGI::Base;
use URI::Escape  qw(uri_escape uri_unescape);
use CGI::Carp;
@ISA = qw(CGI::Base);

$revision='$Id: BasePlus.pm,v 2.72 1995/11/26 04:54:10 lstein Exp $';
($VERSION=$revision)=~s/.*(\d+\.\d+).*/$1/;

=head1 NAME

CGI::BasePlus - HTTP CGI Base Class with Handling of Multipart Forms

=head1 DESCRIPTION

This module implements a CGI::BasePlus object that is identical in
behavior to CGI::Base except that it provides special handling for
postings of MIME type multipart/form-data (which may get very long).
In the case of these types of postings, parts that are described
as being from a file upload are copied into a temporary file in
/usr/tmp, a filehandle is opened on the temporary files, and the name
of the filehandle is returned to the caller in the
$CGI::Base:QUERY_STRING variable.

Please see L<CGI::Base> for more information.

=head2 SEE ALSO

URI::URL, CGI::Request, CGI::MiniSvr, CGI::Base

=cut
    ;

############ SUPPORT ROUTINES FOR THE NEW MULTIPART ENCODING ##########
package MultipartBuffer;

# how many bytes to read at a time.  We use
# a 5K buffer by default.
$FILLUNIT = 1024 * 5;		
$CRLF="\r\n";

sub new {
    my($package,$boundary,$length,$filehandle) = @_;
    my $IN;
    if ($filehandle) {
	my($package) = caller;
	$IN="$package\:\:$filehandle"; # force into caller's package
    }
    $IN = "main::STDIN" unless $IN;
    my $self = {LENGTH=>$length,
		BOUNDARY=>$boundary,
		IN=>$IN,
		BUFFER=>'',
	    };

    $FILLUNIT = length($boundary) if length($boundary) > $FILLUNIT;
    my($null)='';

    # remove the topmost boundary line so that our
    # first read begins with data.
    read($IN,$null,length($boundary)+2);
    $self->{LENGTH}-=(length($boundary)+2);

    return bless $self,$package;
}

# This reads and returns the header as an associative array.
# It looks for the pattern CRLF/CRLF to terminate the header.
sub readHeader {
    my($self) = @_;
    my($end);
    do {
	$self->fillBuffer($FILLUNIT);
    } until
	(($end = index($self->{BUFFER},"$CRLF$CRLF")) >= 0)
	    || ($self->{BUFFER} eq '');
    my($header) = substr($self->{BUFFER},0,$end+2);
    substr($self->{BUFFER},0,$end+4) = '';
    my %return;
    while ($header=~/^([\w-]+): (.*)$CRLF/mog) {
	$return{$1}=$2;
    }
    return %return;
}

# This reads and returns the body as a single scalar value.
sub readBody {
    my($self) = @_;
    my($data,$returnval);
    while ($data = $self->read) {
	$returnval .= $data;
    }
    return $returnval;
}

# This will read $bytes or until the boundary is hit, whichever happens
# first.  After the boundary is hit, we return undef.  The next read will
# skip over the boundary and begin reading again;
sub read {
    my($self,$bytes) = @_;
    $bytes = $bytes || $FILLUNIT;	# default number of bytes to read

    # Fill up our internal buffer in such a way that the boundary
    # is never split between reads.
    $self->fillBuffer($bytes);

    # Find the boundary in the buffer (it may not be there).
    my $start = index($self->{BUFFER},$self->{BOUNDARY});

    # If the boundary begins the data, then skip past it
    # and return undef.  The +2 here is a fiendish plot to
    # remove the CR/LF pair at the end of the boundary.
    # the boundary.
    if ($start == 0) {

	# clear us out completely if we've hit the last boundary.
	if (index($self->{BUFFER},"$self->{BOUNDARY}--")==0) {
	    $self->{BUFFER}='';
	    $self->{LENGTH}=0;
	    return undef;
	}

	# just remove the boundary.
	substr($self->{BUFFER},0,length($self->{BOUNDARY})+2)='';
	return undef;
    }

    my $bytesToReturn;    
    if ($start > 0) {		# read up to the boundary
	$bytesToReturn = $start > $bytes ? $bytes : $start;
    } else {			# read the requested number of bytes
	$bytesToReturn = $bytes;
    }

    my $returnval=substr($self->{BUFFER},0,$bytesToReturn);
    substr($self->{BUFFER},0,$bytesToReturn)='';
    
    # If we hit the boundary, then remove the extra CRLF/CRLF from
    # the end (I think this is a Netscape bug, but who knows?)
    return ($start > 0) ? substr($returnval,0,-4) : $returnval;
}

# This fills up our internal buffer in such a way that the
# boundary is never split between reads
sub fillBuffer {
    my($self,$bytes) = @_;
    my($boundaryLength) = length($self->{BOUNDARY});
    my($bufferLength) = length($self->{BUFFER});
    my($bytesToRead) = $bytes - $bufferLength + $boundaryLength + 2;
    $bytesToRead = $self->{LENGTH} if $self->{LENGTH} < $bytesToRead;
    my $bytesRead = read($self->{IN},$self->{BUFFER},$bytesToRead,$bufferLength);
    $self->{LENGTH} -= $bytesRead;
}

# Return true when we've finished reading
sub eof {
    my($self) = @_;
    return 1 if (length($self->{BUFFER}) == 0)
		 && ($self->{LENGTH} <= 0);
}

package TempFile;

@TEMP=('/usr/tmp','/var/tmp','/tmp',);

foreach (@TEMP) {
    do {$TMPDIRECTORY = $_; last} if -w $_;
}
$TMPDIRECTORY  = "." unless $TMPDIRECTORY;
$SEQUENCE="CGItemp$$0000";

%OVERLOAD = ('""'=>'as_string');

# Create a temporary file that will be automatically
# unlinked when finished.
sub new {
    my($package) = @_;
    $SEQUENCE++;
    my $self = "$TMPDIRECTORY/$SEQUENCE";
    return bless \$self;
}

sub DESTROY {
    my($self) = @_;
    unlink $$self;		# get rid of the file
}

sub as_string {
    my($self) = @_;
    return $$self;
}

############ OVERRIDDEN ROUTINES IN CGI::Base ##########
package CGI::BasePlus;

# Read entity body in such a way that file uploads are stored
# to temporary disk files.  See below.
sub read_post_body {
    my $self = shift;

    # Use parent's read_post_body() method unless we have a
    # new multipart/form-data type of body to deal with.
    return &CGI::Base::read_post_body($self)
	unless $CGI::Base::CONTENT_TYPE =~ m|^multipart/form-data|;

    # Handle multipart/form-data postings.  For compatability
    # with the Request.pm module, the name/value pairs are
    # converted into canonical (URL-encoded) form and stored
    # into $CGI::Base::QUERY_STRING.
    my($boundary) = $ENV{'CONTENT_TYPE'}=~/boundary=(\S+)/;
    $self->read_multipart($boundary,$ENV{'CONTENT_LENGTH'});
}

sub read_multipart {
    my($self,$boundary,$length) = @_;
    my($buffer) = new MultipartBuffer($boundary,$length);
    my(%header,$body);
    while (!$buffer->eof) {
	%header = $buffer->readHeader;
	# In beta1 it was "Content-disposition".  In beta2 it's "Content-Disposition"
	# Sheesh.
	my($key) = $header{'Content-disposition'} ? 'Content-disposition' : 'Content-Disposition';
	my($param) = $header{$key}=~/ name="(.*?)"/;
	my($filename) = $header{$key}=~/ filename="(.*?)"/;
	
	my($value);

	if ($filename) {
	    # If we get here, then we are dealing with a potentially large
	    # uploaded file.  Save the data to a temporary file, then open
	    # the file for reading, and stash the filehandle name inside
	    # the query string.
	    my($tmpfile) = new TempFile;
	    open (OUT,">$tmpfile") || croak "CGI open of $tmpfile: $!\n";
	    chmod 0666,$tmpfile;	# make sure anyone can delete it.
	    my $data;
	    while ($data = $buffer->read) {
		print OUT $data;
	    }
	    close OUT;

	    # Now create a new filehandle in the caller's namespace.
	    # The name of this filehandle just happens to be identical
	    # to the original filename (NOT the name of the temporary
	    # file, which is hidden!)
	    my($frame)=1;
	    my($cp);
	    do {
		$cp = caller($frame++);
	    } until $cp!~/^CGI/;
	    my($filehandle) = "$cp\:\:$filename";
	    open($filehandle,$tmpfile) || croak "CGI open of $tmpfile: $!\n";
	    
	    $value = $filename;

	    # Under Unix, it is safe to let the temporary file be deleted
	    # when it goes out of scope.  The storage is not deallocated
	    # until the last file descriptor is closed.  So we do nothing
	    # special here.
	}

	# If we get here then we're dealing a non-file form field, which we
	# will assume can fit into memory OK.
	else {
	    $value = $buffer->readBody;
	}

	# Now we store the parameter name and the value into our
	# query string for later retrieval
	$CGI::Base::QUERY_STRING .= '&' if $CGI::Base::QUERY_STRING;
	$CGI::Base::QUERY_STRING .= uri_escape($param) . '=' . uri_escape($value);
    }
    1;
}

$VERSION;			# prevent spurious warning message
