package App::KADR::AniDB::UDP::Message::Request;

use aliased 'App::KADR::AniDB::UDP::Meta::Attribute::Trait::Field';
use App::KADR::AniDB::UDP::Message::Sugar;
use App::KADR::Moose;

extends 'App::KADR::AniDB::UDP::Message';

has_field 's', accessor => 'session_key';
has_field 'tag';

sub stringify {
	my $self = shift;
	my $meta = $self->meta;

	my $params =
		join '&',
		map {
			my $reader = $_->get_read_method;
			$_->name . '=' . $self->$reader;
		}
		grep {
			my $predicate = $_->predicate;
			$_->does(Field) && $self->$predicate;
		}
		$meta->get_all_attributes;

	$meta->req_type . ($params ? ' ' . $params : '') . "\n";
}

1;
