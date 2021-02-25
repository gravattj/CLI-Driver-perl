package CLI::Driver::Action;

use Modern::Perl;
use Moose;
use namespace::autoclean;
use Kavorka '-all';
use Data::Printer alias => 'pdump';
use CLI::Driver::Deprecated;
use CLI::Driver::Class;
use CLI::Driver::Method;
use CLI::Driver::Help;
use Module::Load;
use File::Basename;

with 'CLI::Driver::CommonRole';

###############################
###### PUBLIC ATTRIBUTES ######
###############################

has name => ( is => 'rw', isa => 'Str' );
has desc => ( is => 'rw', isa => 'Str' );

has deprecated => (
    is      => 'rw',
    isa     => 'CLI::Driver::Deprecated',
    default => sub { CLI::Driver::Deprecated->new },
);

# DEPRECATED in favor of 'deprecated'
has is_deprecated => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

has class          => ( is => 'rw', isa => 'CLI::Driver::Class' );
has 'method'       => ( is => 'rw', isa => 'CLI::Driver::Method' );
has 'help'         => ( is => 'rw', isa => 'CLI::Driver::Help' );
has 'use_argv_map' => ( is => 'rw', isa => 'Bool' );

##############################################################
# PUBLIC METHODS
##############################################################

method parse (HashRef :$href!) {

    $self->_handle_class($href)  or return 0;
    $self->_handle_method($href) or return 0;
    $self->_handle_deprecation($href);
    $self->_handle_desc($href);
    $self->_handle_help($href);

    return 1;
}

method usage {

    printf "\nusage: %s %s [opts] [-?]\n\n", basename($0), $self->name;
    printf "description: %s\n\n", $self->desc if $self->desc;

    my $help = $self->help;

    my @opts;
    push @opts, @{ $self->class->attr };
    push @opts, @{ $self->method->args };

    #
    # handle required
    #
    my %opts;
    foreach my $opt (@opts) {

        if ( $opt->required ) {
            $opts{ $opt->cli_arg } = $opt;
        }
    }

    foreach my $arg ( sort { uc($a) cmp uc($b) } keys %opts ) {

        my $opt = $opts{$arg};
        printf "\t%s\n", $opt->get_usage($arg);
        printf "\t\t%s\n", $help->get_usage($arg) if $help->has_help($arg);
    }

    #
    # handle optional
    #
    %opts = ();
    foreach my $opt (@opts) {

        if ( $opt->is_optional and !$opt->is_flag ) {
            $opts{ $opt->cli_arg } = $opt;
        }
    }

    foreach my $arg ( sort { uc($a) cmp uc($b) } keys %opts ) {

        my $opt = $opts{$arg};
        printf "\t[ %s ]\n", $opt->get_usage($arg);
        printf "\t\t%s\n", $help->get_usage($arg) if $help->has_help($arg);
    }

    #
    # handle flags
    #
    %opts = ();
    foreach my $opt (@opts) {

        if ( $opt->is_flag ) {
            $opts{ $opt->cli_arg } = $opt;
        }
    }

    foreach my $arg ( sort { uc($a) cmp uc($b) } keys %opts ) {
        
        my $opt = $opts{$arg};
        printf "\t[ %s ]\n", $opt->get_usage($arg);
        printf "\t\t%s\n", $help->get_usage($arg) if $help->has_help($arg);
    }

    #
    # handle examples
    #
    if ( $help->has_examples ) {

        my $cmd = sprintf "%s %s", basename($0), $self->name;

        print "\n";
        print "Examples:\n";
        foreach my $eg ( @{ $help->examples } ) {
            printf "\t%s %s\n", $cmd, $eg;
        }
    }

    #########################################################################

    print "\n";
    exit;
}

method _new_class {

    my $class      = $self->class;
    my $class_name = $class->name;
    my %attr       = $class->get_signature;

    load $class_name;
    my $obj =
      $class_name->new( %attr, use_argv_map => $self->use_argv_map ? 1 : 0 );

    #
    # validate required class attributes were provided
    #
    my @soft_req = $class->find_req_attrs( hard => 0, soft => 1 );

    foreach my $opt (@soft_req) {

        my $attr = $opt->method_arg;

        if ( !defined $obj->$attr ) {
            confess "failed to determine $attr";
        }
    }

    return $obj;
}

method do {

    #
    # this creates an instance of the user class defined in the yaml
    #
    my $obj = $self->_new_class;

    #
    # prepare the method args from @ARGV or %ARGV
    #
    my $method      = $self->method;
    my $method_name = $method->name;
    my %sig         = $method->get_signature;

    if ( $self->use_argv_map ) {
        if ( keys %ARGV ) {
            my @argv = %ARGV;
            $self->die("extra args detected: @argv");
        }
    }
    else {
        if (@ARGV) {
            $self->die("extra args detected: @ARGV");
        }
    }

    #
    # finally invoke the actual method
    #
    return $obj->$method_name(%sig);
}

##############################################################
# PRIVATE METHODS
##############################################################

method _handle_deprecation (HashRef $href!) {

    #
    # is_deprecated: <bool>
    #
    my $has_is_deprecated = 0;
    if ( defined $href->{is_deprecated} ) {

        $has_is_deprecated = 1;
        my $bool = $self->str_to_bool( $href->{is_deprecated} );
        $self->is_deprecated($bool);
    }

    #
    # deprecated:
    #   status: <bool>
    #
    my $has_deprecated = 0;
    if ( defined $href->{deprecated} ) {

        $has_deprecated = 1;
        my $depr = $self->deprecated;
        if ( !$depr->parse( href => $href->{deprecated} ) ) {
            $self->warn(
                sprintf( "%s: failed to parse 'deprecated' section",
                    $self->name )
            );
        }
    }

    #
    # sync them up
    #
    if ( $has_is_deprecated and $has_deprecated ) {

        # these should match
        if ( $self->is_deprecated != $self->deprecated->status ) {
            $self->warn( sprintf( "%s: deprecation mismatch", $self->name ) );
        }
    }
    elsif ($has_is_deprecated) {
        $self->deprecated->status( $self->is_deprecated );
    }
    elsif ($has_deprecated) {
        $self->is_deprecated( $self->deprecated->status );
    }
}

method _handle_class (HashRef $href!) {

    if ( $href->{class} ) {

        my $class = CLI::Driver::Class->new(
            use_argv_map => $self->use_argv_map ? 1 : 0 );
        my $success = $class->parse( href => $href->{class} );
        if ( !$success ) {
            return 0;
        }

        $self->class($class);
        return 1;
    }

    return 0;
}

method _handle_method (HashRef $href!) {

    if ( $href->{method} ) {

        my $method = CLI::Driver::Method->new(
            use_argv_map => $self->use_argv_map ? 1 : 0 );
        my $success = $method->parse( href => $href->{method} );
        if ( !$success ) {
            return 0;
        }

        $self->method($method);
        return 1;
    }

    return 0;
}

method _handle_desc (HashRef $href!) {

    if ( $href->{desc} ) {
        $self->desc( $href->{desc} );
    }
}

method _handle_help (HashRef $href!) {

    my $help = CLI::Driver::Help->new;
    $help->parse( href => $href->{help} );
    $self->help($help);
}

method _get_deprecated_msg {

    my $msg = "DEPRECATED";
    if ( $self->deprecated->replaced_by ) {
        $msg .= " by " . $self->deprecated->replaced_by;
    }

    return sprintf "(%s)", $msg;
}

1;
