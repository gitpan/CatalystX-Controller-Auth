package CatalystX::Controller::Auth;

use 5.006;
use strict;
use warnings;

=head1 NAME

CatalystX::Controller::Auth - The great new CatalystX::Controller::Auth!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

use Moose;
use namespace::autoclean;

use HTML::FormHandlerX::Form::Login;

has login_id_field             => ( is => 'ro', isa => 'Str', default => 'username' );
has login_id_db_field          => ( is => 'ro', isa => 'Str', default => 'username' );

has login_template             => ( is => 'ro', isa => 'Str', default => 'auth/login.tt');
has change_password_template   => ( is => 'ro', isa => 'Str', default => 'auth/change-password.tt' );
has forgot_password_template   => ( is => 'ro', isa => 'Str', default => 'auth/forgot-password.tt' );
has reset_password_template    => ( is => 'rw', isa => 'Str', default => 'auth/reset-password.tt' );

has login_required_message     => ( is => 'ro', isa => 'Str', default => "You need to login." );
has already_logged_in_message  => ( is => 'ro', isa => 'Str', default => "You are already logged in." );
has login_successful_message   => ( is => 'ro', isa => 'Str', default => "You have logged in." );
has logout_successful_message  => ( is => 'ro', isa => 'Str', default => "You have been logged out." );
has login_failed_message       => ( is => 'ro', isa => 'Str', default => "Bad username or password." );
has password_changed_message   => ( is => 'ro', isa => 'Str', default => "Password changed." );
has password_reset_message     => ( is => 'ro', isa => 'Str', default => "Password reset successfully." );
has forgot_password_id_unknown => ( is => 'ro', isa => 'Str', default => "Email address not registered." );

has action_after_login           => ( is => 'ro', isa => 'Str', default => '/' );
has action_after_change_password => ( is => 'ro', isa => 'Str', default => '/' );

has forgot_password_email_from           => ( is => 'ro', isa => 'Str', default => '' );
has forgot_password_email_subject        => ( is => 'ro', isa => 'Str', default => 'Forgot Password' );
has forgot_password_email_template_plain => ( is => 'ro', isa => 'Str', default => 'reset-password-plain.tt' );

has reset_password_salt        => ( is => 'ro', isa => 'Str', default => "abc123" );

BEGIN { extends 'Catalyst::Controller'; }

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use CatalystX::Controller::Auth;

    my $foo = CatalystX::Controller::Auth->new();
    ...

=head2 base

Empty.

=cut

sub base :Chained('/base') :PathPart('') :CaptureArgs(0)
{
	my ( $self, $c ) = @_;
}

=head2 authenticated ( mid-point: / )

Chain off this action to make sure people are logged in.

=cut

sub authenticated :Chained('base') :PathPart('') :CaptureArgs(0)
{
	my ( $self, $c ) = @_;
	
	if ( ! $c->user_exists )
	{
		$c->response->redirect( $c->uri_for( $self->action_for('login'), { mid => $c->set_error_msg( $self->login_required_message ) } ) );
		return;
	}
}

=head2 login ( end-point: /login )

Login, redirect if already logged in.

=cut

sub login :Chained('base') :PathPart :Args(0)
{
	my ( $self, $c ) = @_;

	if ( $c->user_exists )
	{
		$c->response->redirect( $c->uri_for_action( $self->action_after_login, { mid => $c->set_status_msg( $self->already_logged_in_message ) } ) );
		return;
	}

	my $form = HTML::FormHandlerX::Form::Login->new( active => [ $self->login_id_field, 'password' ] );
	
	if ( $c->req->method eq 'POST' )
	{
		$form->process( params => $c->request->params );

		if ( $form->validated )
		{
			if ( $c->authenticate( { $self->login_id_db_field => $form->field( $self->login_id_field )->value, password => $form->field('password')->value } ) )
			{
				if ( $c->req->params->{ remember } )
	 			{
					$c->response->cookies->{ remember } = { value => $form->field( $self->login_id_field )->value };
				}
				else
				{
					$c->response->cookies->{ remember } = { value => '' };
				}

				$c->response->redirect( $c->uri_for_action( $self->action_after_login, { mid => $c->set_status_msg( $self->login_successful_message ) } ) );
				return;
			}
			else
			{
				$c->stash( error_msg => $self->login_failed_message );
			}
		}
	}

	$c->stash( template => $self->login_template, form => $form );
}

=head2 login ( end-point: /logout )

Logs out, and redirects back to /login.

=cut

sub logout :Chained('base') :PathPart :Args(0)
{
	my ( $self, $c ) = @_;

	$c->logout;

	$c->response->redirect( $c->uri_for( $self->action_for( 'login' ), { mid => $c->set_status_msg( $self->logout_successful_message ) } ) );
}

=head2 get ( mid-point: /auth/*/ )

Gets a user and puts them in the stash.

=cut

sub get :Chained('base') :PathPart('auth') :CaptureArgs(1)
{
	my ( $self, $c, $id ) = @_;

	my $user = $c->model('DB::User')->find( $id );

	if ( ! $user )
	{
		$c->response->redirect( $c->uri_for( $self->action_for('login'), { mid => $c->set_status_msg( $self->login_required_message ) } ) );
		return;
	}

	$c->stash( user => $user );
}

=head2 change_password ( end-point: /auth/*/change-password/ )

Change your password.

=cut

sub change_password :Chained('get') :PathPart('change-password') :Args(0)
{
	my ( $self, $c ) = @_;

	my $form = HTML::FormHandlerX::Form::Login->new( active => [ qw( old_password password confirm_password ) ] );
	
	if ( $c->req->method eq 'POST' )
	{
		$form->process( params => $c->request->params );

		if ( $form->validated )
		{
			my $user = $c->stash->{ user };

			if ( ! $c->authenticate( { $self->login_id_db_field => $user->email, password => $form->field('old_password')->value } ) )
			{
				$c->stash( error_msg => 'Old password incorrect' );
			}
			else
			{
				$user->password( $form->field('password')->value );
			
				$user->update;	

		 		$c->response->redirect( $c->uri_for_action( $self->action_after_change_password, { mid => $c->set_status_msg( $self->password_changed_message ) } ) );
				return;
			}
		}
	}

	$c->stash( template => $self->change_password_template, form => $form );
}


=head2 forgot_password ( end-point: /auth/*/forgot-password/ )

Send a forgotten password toekn to reset it.

=cut

sub forgot_password :Chained('base') :PathPart('forgot-password') :Args(0)
{
	my ( $self, $c ) = @_;

	my $form = HTML::FormHandlerX::Form::Login->new( active => [ qw( email ) ] );
	
	if ( $c->req->method eq 'POST' )
	{
		$form->process( params => $c->request->params );

		if ( $form->validated )
		{
		 	my $user = $c->model('DB::User')->find( { $self->login_id_db_field => $c->request->params->{ $self->login_id_field } } );

		 	if ( $user )
		 	{
		 		$c->stash( user => $user );
		 		
				$form->token_salt( $self->password_reset_message );

				$form->add_token_field( $self->login_id_field );

				my $token = $form->token;

				$c->stash( token => $token );

				# send reset password username to the user
				
				$c->stash->{ email_template } = { to           => $user->email,
				                                  from         => $self->forgot_password_email_from,
				                                  subject      => $self->forgot_password_email_subject,
				                                  content_type => 'multipart/alternative',
				                                  templates => [
				                                                 { template        => $self->forgot_password_email_template_plain,
				                                                   content_type    => 'text/plain',
				                                                   charset         => 'utf-8',
				                                                   encoding        => 'quoted-printable',
				                                                   view            => 'TT', 
				                                                 }
				                                               ]
				};
			        
			        $c->forward( $c->view('Email::Template') );

				$c->stash( status_msg => "Password reset link sent to " . $user->email );
			}
			else
			{
				$c->stash( error_msg => $self->forgot_password_id_unknown );
			}
		}
	}

	$c->stash( template => $self->forgot_password_template, form => $form );
}

=head2 reset_password ( end-point: /auth/*/reset-password/ )

Reset password using a token sent in an username.

=cut

sub reset_password :Chained('base') :PathPart('reset-password') :Args(0)
{
	my ( $self, $c ) = @_;

	if ( $c->req->method eq 'GET' && ! $c->request->params->{ token } )
	{
		$c->response->redirect( $c->uri_for( $self->action_for('forgot_password'), { mid => $c->set_status_msg("Missing token") } ) );
		return;
	}
	
	my $form;
	
	if ( $c->req->method eq 'GET' )
	{
		$form = HTML::FormHandlerX::Form::Login->new( active => [ qw( token ) ] );

		$form->token_salt( $self->password_reset_message );

		$form->add_token_field( $self->login_id_field );

		$form->process( params => { token => $c->request->params->{ token } } );
		
		if ( ! $form->validated )
		{
			$c->response->redirect( $c->uri_for( $self->action_for('forgot_password'), { mid => $c->set_error_msg("Invalid token") } ) );
			return;
		}
	}
	
	if ( $c->req->method eq 'POST' )
	{
		$form = HTML::FormHandlerX::Form::Login->new( active => [ qw( token password confirm_password ) ] );
	
		$form->token_salt( $self->password_reset_message );
		
		$form->add_token_field( $self->login_id_field );

		$form->process( params => $c->request->params );

		if ( $form->validated )
		{
			my $user = $c->model('DB::User')->find( { $self->login_id_db_field => $form->field( $self->login_id_field )->value } );
			
			$user->password( $form->field('password')->value );
			
			$user->update;	

	 		$c->response->redirect( $c->uri_for( $self->action_for('login'), { mid => $c->set_status_msg( $self->password_reset_message ) } ) );
			return;
		}
	}
	
	$c->stash( template => $self->reset_password_template, form => $form );
}

=head1 AUTHOR

Rob Brown, C<< <rob at intelcompute.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-catalystx-controller-auth at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CatalystX-Controller-Auth>.  I will be notified, and then you will
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CatalystX::Controller::Auth


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CatalystX-Controller-Auth>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CatalystX-Controller-Auth>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CatalystX-Controller-Auth>

=item * Search CPAN

L<http://search.cpan.org/dist/CatalystX-Controller-Auth/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Rob Brown.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of CatalystX::Controller::Auth
