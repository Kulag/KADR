use common::sense;
use Test::More;
use Test::Trap;

use App::KADR::Pid;

my $pf = App::KADR::Pid->new;

ok !$pf->is_running, 'pid not written, so not running';

$pf->write(9999);
is $pf->pid, 9999, 'can write arbitrary pid';
ok -f $pf->file && -r $pf->file, 'pid file exists';

$pf->write;
is $pf->pid, $$, 'wrote own pid';
is $pf->is_running, $$, 'self is running';

$pf->remove;
ok !-f $pf->file, 'deletion okay';

App::KADR::Pid->import('-onlyone');
trap { App::KADR::Pid->import('-onlyone') };
is $trap->exit, 1, 'exited with error';
like $trap->stdout, qr/Another instance/, 'right error';

done_testing;
