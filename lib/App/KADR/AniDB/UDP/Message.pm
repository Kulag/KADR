package App::KADR::AniDB::UDP::Message;

# Let MarkAsMethods handle cleaning to preserve the overload.
use App::KADR::Moose -noclean => 1;
use MooseX::MarkAsMethods autoclean => 1;

use overload '""' => sub { shift->stringify };
