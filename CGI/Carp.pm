package CGI::Carp;

=head1 NAME

B<CGI::Carp> - CGI routines for writing to the HTTPD (or other) error log

=head1 SYNOPSIS

    use CGI::Carp;

    croak "We're outta here!";
    confess "It was my fault: $!";
    carp "It was your fault!";   
    warn "I'm confused";
    die  "I'm dying.\n";

=head1 DESCRIPTION

CGI scripts have a nasty habit of leaving warning messages in the error
logs that are neither time stamped nor fully identified.  Tracking down
the script that caused the error is a pain.  This fixes that.  Replace
the usual

    use Carp;

with

    use CGI::Carp

And the standard warn(), die (), croak(), confess() and carp() calls
will automagically be replaced with functions that write out nicely
time-stamped messages to the HTTP server error log.

For example:

   [Fri Nov 17 21:40:43 1995] test.pl: I'm confused at test.pl line 3.
   [Fri Nov 17 21:40:43 1995] test.pl: Got an error message: Permission denied.
   [Fri Nov 17 21:40:43 1995] test.pl: I'm dying.

=head1 REDIRECTING ERROR MESSAGES

By default, error messages are sent to STDERR.  Most HTTPD servers
direct STDERR to the server's error log.  Some applications may wish
to keep private error logs, distinct from the server's error log, or
they may wish to direct error messages to STDOUT so that the browser
will receive them (for debugging, not for public consumption).

The C<carpout()> function is provided for this purpose.  Since
carpout() is not exported by default, you must import it explicitly by
saying

   use CGI::Carp qw(carpout);

The carpout() function requires one argument, which should be a
reference to an open filehandle for writing errors.  It should be
called in a C<BEGIN> block at the top of the CGI application so that
compiler errors will be caught.  Example:

   BEGIN {
     use CGI::Carp qw(carpout);
     open(LOG, ">>/usr/local/cgi-logs/mycgi-log") or
       die("Unable to open mycgi-log: $!\n");
     carpout(LOG);
   }

carpout() does not handle file locking on the log for you at this point.

If you want to send errors to the browser, give carpout() a reference
to STDOUT:

   BEGIN {
     use CGI::Carp qw(carpout);
     carpout(STDOUT);
   }

If you do this, be sure to send a Content-Type header immediately --
perhaps even within the BEGIN block -- to prevent server errors.

The real STDERR is not closed -- it is moved to SAVEERR.  Some
servers, when dealing with CGI scripts, close their connection to the
browser when the script closes STDOUT and STDERR.  SAVEERR is used to
prevent this from happening prematurely.

You can pass filehandles to carpout() in a variety of ways.  The "correct"
way according to Tom Christiansen is to pass a reference to a filehandle 
GLOB:

    carpout(\*LOG);

This looks weird to mere mortals however, so the following syntaxes are
accepted as well:

    carpout(LOG);
    carpout(main::LOG);
    carpout(main'LOG);
    carpout(\LOG);
    carpout(\'main::LOG');

    ... and so on

Use of carpout() is not great for performance, so it is recommended
for debugging purposes or for moderate-use applications.  A future
version of this module may delay redirecting STDERR until one of the
CGI::Carp methods is called to prevent the performance hit.

=head1 AUTHORS

Lincoln D. Stein <lstein@genome.wi.mit.edu>.  Feel free to redistribute
this under the Perl Artistic License.

carpout() added and minor corrections by Marc Hedlund
<hedlund@best.com> on 11/26/95.

=head1 SEE ALSO

Carp, CGI::Base, CGI::BasePlus, CGI::Request, CGI::MiniSvr, CGI::Form,
CGI::Response

=cut

require 5.000;
use Exporter;
use Carp;

@ISA = qw(Exporter);
@EXPORT = qw(confess croak carp);
@EXPORT_OK = qw(carpout);

$main::SIG{__WARN__}='CGI::Carp::warn';
$main::SIG{__DIE__}='CGI::Carp::die';
$CGI::Carp::VERSION = '1.02';

# These are the originals
sub realwarn { warn(@_); }
sub realdie { die(@_); }

sub id {
    my $level = shift;
    my($pack,$file,$line,$sub) = caller($level);
    my($id) = $file=~m|([^/]+)$|;
    return ($file,$line,$id);
}

sub stamp {
    my $time = scalar(localtime);
    my $frame = 0;
    my ($id,$pack,$file);
    do {
	$id = $file;
	($pack,$file) = caller($frame++);
    } until !$file;
    ($id) = $id=~m|([^/]+)$|;
    return "[$time] $id: ";
}

sub warn {
    my $message = shift;
    my($file,$line,$id) = id(1);
    $message .= " at $file line $line.\n" unless $message=~/\n$/;
    my $stamp = stamp;
    $message=~s/^/$stamp/gm;
    realwarn $message;
}

sub die {
    my $message = shift;
    my $time = scalar(localtime);
    my($file,$line,$id) = id(1);
    $message .= " at $file line $line.\n" unless $message=~/\n$/;
    my $stamp = stamp;
    $message=~s/^/$stamp/gm;
    realdie $message;
}

sub confess { CGI::Carp::die Carp::longmess @_; }
sub croak { CGI::Carp::die Carp::shortmess @_; }
sub carp { CGI::Carp::warn Carp::shortmess @_; }

# We have to be ready to accept a filehandle as a reference
# or a string.
sub carpout {
    my($in) = @_;
    $in = $$in if ref($in); # compatability with Marc's method;
    my($no) = fileno($in);
    unless (defined($no)) {
	my($package) = caller;
	my($handle) = $in=~/[':]/ ? $in : "$package\:\:$in"; 
	$no = fileno($handle);
    }
    die "Invalid filehandle $in\n" unless $no;
    
    open(SAVEERR, ">&STDERR");
    open(STDERR, ">&$no") or 
	( print SAVEERR "Unable to redirect STDERR: $!\n" and exit(1) );
}

1;
