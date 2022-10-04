package Dancer2::RPCPlugin::EndpointConfigFactory;
use Moo;
use Types::Standard qw( Maybe Enum HashRef CodeRef InstanceOf Str );

=head1 NAME

Dancer2::RPCPlugin::EndpointConfigFactory - Takes away the details of L<Dancer2::Plugin::RPC>

=head1 SYNOPSIS

    use Dancer ':syntax';
    use Bread::Board;
    use Dancer2::RPCPlugin::EndpointConfigFactory;
    my $config = Dancer2::RPCPlugin::EndpointConfigFactory->new(
        publish     => 'pod',
        bread_board => container(
            app => as {
                container apis => as {
                    service 'Example::API::MetaCpan' => as (
                        class => 'Example::API::MetaCpan',
                        dependencies => {
                            # attributes needed for instantiation
                            # or objects from the same container
                            mc_client => '../clients/Client::MetaCpan',
                        },
                    ),
                };
                container clients => as {
                    service 'Client::MetaCpan' => as (
                        class => 'Client::MetaCpan',
                        dependencies => {
                            base_uri => literal config->{base_uri},
                    ),
                };
            };
        ),
    );

    $config->register_endpoint('RPC::JSONRPC' => '/metacpan');
    $config->register_endpoint('RPC::XMLRPC'  => '/metacpan');

=head1 ATTRIBUTES

=head2 publish  [required]

This attribute can have the value of B<config> or B<pod>, it will be bassed to
L<Dancer2::Plugin::RPC>

=head2 callback [optional]

This attribute is passed directly to L<Dancer2::Plugin::RPC>

=head2 bread_board [required]

This is an instatiated L<Bread::Board::Container> object, that defines the
components of this service and their interaction.

=head2 code_wrapper [optional/lazy]

The code-wrapper is passed to L<Dancer2::Plugin::RPC>. The default code-wrapper
uses the L<Bread::Board::Container> to spawn the code for the
Remote-Procedure-Call.

=head2 plugin_arguments [optional]

This hashref is directly passed to L<Dancer2::Plugin::RPC>

=cut

has publish => (
    is       => 'ro',
    isa      => Enum[qw( config  pod )],
    required => 1
);
has callback => (
    is       => 'ro',
    isa      => Maybe[CodeRef],
    required => 0
);
has bread_board => (
    is       => 'ro',
    isa      => InstanceOf['Bread::Board::Container'],
    required => 1
);
has code_wrapper => (
    is   => 'lazy',
    isa  => CodeRef,
);
has plugin_arguments => (
    is       => 'ro',
    isa      => Maybe[HashRef],
    required => 0,
);

my %_plugin_info;
use Dancer2::RPCPlugin::PluginNames;

sub BUILD{
    my $self = shift;
    my $caller = caller(1);

    my $pn = Dancer2::RPCPlugin::PluginNames->new();
    for my $plugin_name ($pn->names) {
        my $plugin = "Dancer2::Plugin::RPC::\U$plugin_name";
        eval "use $plugin";
        die "Cannot load $plugin: $@" if $@;
        $_plugin_info{"RPC::\U$plugin_name"} = {
            name      => $plugin_name,
            registrar => $plugin->can("$caller\::$plugin_name"),
            caller    => $caller,
        };
    }
}

=head1 DESCRIPTION

Weird object with sort of a singletonish way of working...

=cut

sub _build_code_wrapper {
    my $self = shift;
    return sub {
        my ($code, $package, $method, @arguments) = @_;
        my $instance = $self->bread_board->resolve(service => "apis/$package");
        use Dancer2;
        debug("$package \-> $method(@arguments)");
        return $instance->$code(@arguments);
    };
}

sub _registrar_for_plugin {
    my $self = shift;
    my ($plugin) = @_;

    return $_plugin_info{$plugin}{registrar} // die "Cannot find plugin '$plugin'";
}

=head2 endpoint_config($path)

Returns a config-hash for the C<Dancer2::Plugin::RPC::*> plugins.

=cut

sub endpoint_config {
    my $self = shift;
    my ($path) = @_;

    return {
        publish      => $self->publish,
        code_wrapper => $self->code_wrapper,
        (defined $self->callback
            ? (callback => $self->callback)
            : ()
        ),
        (defined $self->plugin_arguments
            ? (%{ $self->plugin_arguments })
            : ()
        ),
    };
}

=head2 register_endpoint($plugin, $path)

=cut

sub register_endpoint {
    my $self = shift;
    my ($plugin, $path) = @_;

    my $registrar = $self->_registrar_for_plugin($plugin);
    $registrar->($path, $self->endpoint_config($path));
}

use namespace::autoclean;
1;

=head1 COPYRIGHT

E<copy> MMXXI - Abe Timmerman <abeltje@cpan.org>

=cut

