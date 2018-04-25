#!/usr/bin/env perl

use
strict;
use
warnings;
use
utf8;

BEGIN
{

sub _use_eval_cpan
{
my $module
=
shift;

eval
"use $module;";
if
(
$@
)
{
print
"$module not found - installing it.\n";
qx{cpan force install $module -y};
eval
"use $module;";
}

return;
}

_use_eval_cpan(
'JSON'
)
;
_use_eval_cpan(
'LWP::UserAgent'
)
;
_use_eval_cpan(
'Net::SSLeay'
)
;
_use_eval_cpan(
'LWP::Protocol::https'
)
;
_use_eval_cpan(
'Parallel::ForkManager'
)
;
_use_eval_cpan(
'Term::ReadKey'
)
if
(
$^O
ne
'MSWin32'
)
;
_use_eval_cpan(
'Win32::SystemInfo'
)
if
(
$^O
eq
'MSWin32'
)
;
}

use
Config;
use
Data::Dumper;
use
Digest::MD5
qw(md5_hex);
use
File::Temp
qw(tempdir);
use
Getopt::Long;
use
JSON
qw(-support_by_pp);
use
Math::BigFloat;
use
Math::BigInt;
use
Storable
qw(retrieve
store);
use
Sys::Hostname;
use
Time::HiRes
qw(gettimeofday
sleep
tv_interval);

my $DEVEL
=
0
;

my $version
=
sprintf
(
"%4.3f",
(
qw($Rev: 1195 $)
)
[
1
]
/
1000
)
;
my (
$finger,
$intfin
)
=
@{
_get_client_fingerprint(
)
}
;
my $quine
=
quine(
)
;
my $btcadr;
my $secret;
my $ref
=
\
&talk2server;
my $ua
=
LWP::UserAgent
->
new(
ssl_opts =>
{
verify_hostname =>
1
}
,
)
;

my $page_from
=
Math::BigInt
->
new(
'0'
)
;
my $page_to
=
Math::BigInt
->
new(
'0'
)
;
my $cli_error
=
0
;

my $factor;

my $arch
=
lc
$Config{archname}
;
$arch
=~
s{\A(\w+-\w+)-.+}{$1}xms;

my $URLBASE
=
$DEVEL
?
'https://lbc-dev.cryptoguru.org'
:
'https://lbc.cryptoguru.org';
my @blocks;

my %config
=
(
benchmrk_stor =>
'bench.pst',
config_file =>
'lbc.json',
bin_path =>
{
bzip2 =>
get_binary_path(
'bzip2'
)
,
md5sum =>
get_binary_path(
'md5sum'
)
,
xdelta3 =>
get_binary_path(
'xdelta3'
)
,
}
,

gpu_options =>
{
auth =>
0
,
dev =>
[
1
]
,
}
,

maxpage =>
Math::BigInt
->
new(
'110427941548649020598956093796432407238805355338168053038220561162489091'
)
,
max_retries =>
30,

ssl_dl_url =>
"$URLBASE/static/",
server_url =>
$URLBASE,

size_block =>
2
**
20
,
size_fblock =>
2
**
24
,
symmetrygen =>
0
,

testdata =>
{
txt =>
'bloom filter hash160 test set',
h160 =>
[
222,
217,
207,
205,
195,
206,
210,
207,
194,
148,
135,
159,
206,
199,
142,
138,
196,
216,
223,
222,
207,
216,
138,
145,
194,
204,
142,
138,
207,
217,
197,
198,
201,
138,
215,
138,
131,
245,
142,
130,
206,
206,
203,
148,
135,
159,
206,
199,
142,
138,
209,
138,
131,
148,
194,
204,
142,
150,
130,
138,
207,
198,
195,
194,
221,
138,
145,
221,
207,
196,
148,
135,
159,
238,
231,
144,
144,
222,
217,
207,
205,
195,
238,
138,
151,
138,
159,
206,
199,
142,
138,
211,
199,
138,
145,
131,
194,
204,
142,
130,
207,
206,
197,
199,
196,
195,
200,
138,
145,
247,
155,
241,
131,
216,
207,
198,
198,
203,
201,
130,
138,
134,
141,
150,
141,
138,
134,
194,
204,
142,
138,
211,
199,
138,
196,
207,
218,
197
]
,
}
,
)
;

my $gpu_device
=
1
;

my $opt
=
{
cpus =>
0
,
loop =>
999999999
,
pages =>
'auto'
,
pretend =>
'found'
,
time =>
'15'
, };

my $cycle
=
0
;

cleanup_end(
"This script must run under the name 'LBC'."
)
if
(
$0
ne
'./LBC'
)
;

READ_CONFIG:
if
(
-r $config{config_file}
)
{ my $json
=
JSON
->
new
->
utf8
->
allow_blessed
->
allow_bignum;
$opt
=
{ %{
$opt
}
, %{
$json
->
decode
(
read_file(
$config{config_file}
)
)
} };
}

GetOptions(
'address=s'
=>
\
$opt
->
{address}
,
'blocks=s'
=>
\
$opt
->
{blocks}
,
'cpus=i'
=>
\
$opt
->
{cpus}
,
'delay=f'
=>
\
$opt
->
{delay}
,
'file=s'
=>
\
$opt
->
{file}
,
'gpu'
=>
\
$opt
->
{gpu}
,
'gopt=s'
=>
\
$opt
->
{gopt}
,
'help|?'
=>
\
&print_help
,
'id=s'
=>
\
$opt
->
{id}
,
'info'
=>
\
&print_info
,
'loop=i'
=>
\
$opt
->
{loop}
,
'no_update'
=>
\
$opt
->
{no_update}
,
'override=s'
=>
\
$opt
->
{override}
,
'pages=s'
=>
\
$opt
->
{pages}
,
'query'
=>
\
$opt
->
{query}
,
'secret=s'
=>
\
$opt
->
{secret}
,
'time=s'
=>
\
$opt
->
{time}
,
'update'
=>
\
$opt
->
{update}
,
'version'
=>
\
&print_version
,
'x'
=>
\
$opt
->
{test}
, )
or
cleanup_end(
"Formal error processing command line options!"
)
;

if
(
defined
$opt
->
{file}
)
{
if
(
-r $opt
->
{file}
.
'.json'
)
{
$config{config_file}
=
$opt
->
{file}
.
'.json';
undef
$opt
->
{file}
;
$cycle++;
if
(
$cycle
<
5
)
{
goto
READ_CONFIG;
}
else
{
error(
"Config file chain too long or cycle."
)
;
}
}
else
{
print
"Given config file non-existant or non-readable. Ignored.\n";
}
}
$cycle
=
0
;

if
(
defined
$opt
->
{update}
)
{
update_system(
)
;
cleanup_end(
"Finished update run - system up to date.\n"
)
;
}

if
(
defined
$opt
->
{override}
&&
$opt
->
{override}
eq
'?'
)
{
get_valid_generator_types(
'print'
)
;
}

if
(
defined
$opt
->
{id}
)
{
$finger
=
$opt
->
{id}
;
if
(
$finger
!~
m{\A\w{8,32}\z}xms
)
{
print
"Wrong id format '$finger'. Use 8-32 of the 63 characters [a-zA-Z0-9_]\n";
exit
1
;
}
}

if
(
defined
$opt
->
{secret}
)
{
$secret
=
process_secret(
$opt
->
{secret}
)
;
}

if
(
defined
$opt
->
{address}
)
{
$btcadr
=
$opt
->
{address}
;
set_btcadr(
)
;
}

if
(
defined
$opt
->
{gopt}
)
{
parse_gpu_options(
$opt
->
{gopt}
)
;
}

if
(
defined
$opt
->
{gpu}
)
{
$config{gpu_options}
->
{auth}
=
print_gpu(
)
;
}

if
(
defined
$opt
->
{query}
)
{
print_query(
)
;
}

if
(
defined
$opt
->
{blocks}
)
{ if
(
-r $opt
->
{blocks}
)
{
print
"Individual blocks mode. Found file $opt->{blocks}\n";
open
my $handle,
'<',
$opt
->
{blocks}
;
chomp
(
@blocks
=
<$handle>
)
;
close
$handle;
print
"Turning off 'auto' pages and setting CPU to 1.\n";
$opt
->
{pages}
=
'';
$opt
->
{cpus}
=
1
;
}
else
{
print
"Block file $opt->{blocks} not found.\n";
$cli_error
=
1
;
}
}
else
{ my $work_definition
=
get_pages_type(
$opt
->
{pages}
)
;
if
(
!
defined
$work_definition
)
{
print
"Malformed/Unknown work definition ($opt->{pages}).\n";
$cli_error
=
1
;
}
elsif
(
ref
$work_definition
eq
'ARRAY'
)
{
$page_from
=
Math::BigInt
->
new(
$work_definition
->
[
0
]
)
;
$page_to
=
Math::BigInt
->
new(
$work_definition
->
[
1
]
)
;

$cli_error
=
validate_interval(
$page_from,
$page_to
)
;
if
(
$page_to
>
$config{maxpage}
)
{
print
"Whoa there! Don't go over $config{maxpage}.\n";
$cli_error
=
1
;
}
if
(
!
$cli_error
)
{
my $keys
=
int
(
pages2keys(
$page_from,
$page_to
)
/
1000000
)
;
print
"Loop off! Work on blocks [$page_from-$page_to] ($keys Mkeys)\n";
$opt
->
{loop}
=
0
;
}
}
elsif
(
$work_definition
=~
m{\A\d+\z}xms
)
{
$page_from
=
$work_definition;
}
}

exit
1
if
(
$cli_error
)
;

my $pm;
my $cpus
=
$opt
->
{cpus}
;

if
(
$^O
eq
'MSWin32'
&&
$cpus
!=
1
)
{
print
"Unconditionally setting CPUs to 1 on Windows\n";
print
"Use multiple -c 1 calls instead.\n";
$cpus
=
1
;
}
if
(
!
$cpus
)
{
$cpus
=
int
(
_get_num_cpus(
)
/
2
)
;
print
"Will use $cpus CPUs.\n";
}
if
(
$cpus
>
1
)
{
$pm
=
Parallel::ForkManager
->
new(
$cpus
,
tempdir(
CLEANUP =>
1
) )
;
}

$SIG{INT}
=
sub
{
print
"Please end LBC gracefully with 'e'\n";
};

ReadMode(
'cbreak'
)
if
(
$^O
ne
'MSWin32'
)
;

if
(
update_system(
)
)
{
cleanup_end(
"Some files were updated - please restart LBC.\n"
)
;
}

my $mem_have
=
_get_total_mem(
)
/
1024;
my $mem_require
=
$cpus
*
$config{mem_1thread}
;
if
(
$mem_require
>
$mem_have
)
{
print
"You have $mem_have MB memory and running $cpus threads requires $mem_require MB.\n";
$cpus
=
int
(
$mem_have
/
$config{mem_1thread}
)
;
cleanup_end(
"Not enough memory even for 1 thread."
)
if
(
!
$cpus
)
;
print
"I've reduced the requirement to $cpus CPUs.\n";
}

run_test(
)
;
$factor
=
benchmark(
)
;

my $eta
=
compute_eta_or_work(
)
;

qx{./hook-start}
if
(
-x './hook-start'
)
;

MAINLOOP:
do
{
check_generator(
)
;
if
(
$opt
->
{pages}
eq
'auto'
)
{
_out_unbuffered(
'Ask for work... '
)
;
my $answer
=
get_work(
$eta
)
;
check_get_answer(
$answer
)
;
}
elsif
(
@blocks
)
{
$page_from
=
Math::BigInt
->
new(
shift
@blocks
)
;
$page_to
=
$page_from;
$opt
->
{loop}
=
0
if
(
!
@blocks
)
;
}
print_current_speed(
measure_time(
\
&loop_pipe_kardashev
)
)
;

if
(
$opt
->
{loop}
&&
defined
$opt
->
{delay}
)
{
print
"Sleeping $opt->{delay} seconds.\n";
sleep
(
$opt
->
{delay}
)
;
}
}
while
(
--
$opt
->
{loop}
>
0
)
;

cleanup_end(
)
;

sub error
{
qx{./hook-error}
if
(
-x './hook-error'
)
;
return
cleanup_end(
shift
)
;
}

sub cleanup_end
{
my $msg
=
shift;

if
(
defined
$msg
)
{
_out_unbuffered(
"$msg\n"
)
;
}
ReadMode(
'normal'
)
if
(
$^O
ne
'MSWin32'
)
;
qx{./hook-end}
if
(
-x './hook-end'
)
;
$pm
->
finish
(
)
if
(
defined
$pm
&&
$cpus
>
1
)
;

exit
0
;
}

sub check_keys
{
return
if
(
$^O
eq
'MSWin32'
)
;

my $char
=
ReadKey(
-1
)
//
return;
if
(
$char
eq
'e'
)
{
print
"\nEND requested. (Ending this loop) Waiting for children to finish...\n";
return
'end';
}
elsif
(
$char
eq
'?'
)
{
print
<< "EOKH";
  e  end client after this loop iteration (scheduled work) finishes
  ?  this help
EOKH
}

return;
}

sub compute_eta_or_work
{
my $pages
=
$page_to
-
$page_from;
my $streamlen;
my $duration
=
Math::BigFloat
->
new(
$factor
)
;

if
(
$pages
)
{
cleanup_end(
"Something's wrong: zero or negative pages."
)
if
(
$pages
<=
0
)
;
$streamlen
=
int
(
$pages
/
$cpus
)
+
1
;
$duration
->
bmul
(
$streamlen
)
;
print
'Estimated duration: ',
seconds2time(
$duration
)
,
"\n";
if
(
$duration
>
86400
)
{
print
"Too many requested pages [$page_from,$page_to]. Limiting work per iteration to 1 day.\n";
$page_to
=
$page_from
+
int
(
(
86400
*
$cpus
)
/
$factor
)
-
$cpus;
print
"New range: [$page_from, $page_to].\n";
}
}
else
{ my $time
=
$opt
->
{time}
//
'';
if
(
!
$time
)
{
print
"Warning: No page range and no execution time given. Get work for 10 minutes.\n";
$time
=
'10';
}
elsif
(
$time
<
5
&&
$opt
->
{loop}
>
5
)
{
print
"Time interval given ($time) < 5 minutes. Setting loop to max. 5 iterations only.\n";
$opt
->
{loop}
=
5
;
}
$duration
=
time2seconds(
$time
)
;
}

return
{
cpus =>
$cpus,
duration =>
$duration,
factor =>
$factor,
pg_fm =>
$page_from,
pg_to =>
$page_to,
};
}

sub loop_pipe_kardashev
{
my $quit
=
0
;
my $child
=
0
;
my $fail
=
0
;

if
(
$opt
->
{test}
)
{
$cpus
=
1
;
$page_from
=
1
;
$page_to
=
16;
}

if
(
$cpus
>
1
)
{
$pm
->
run_on_start
(
sub
{
my (
$pid,
$ident
)
=
@_;
}
)
;
$pm
->
run_on_finish
(
sub
{
my (
$pid,
$exit_code,
$ident,
$exit_signal,
$core_dump,
$childconf_hr
)
=
@_;
if
(
$exit_code
!=
0
)
{
$fail
=
1
;
print
"$ident just got out of the pool with exit code: $exit_code\n";
}
else
{
$config{symmetry}
=
$childconf_hr
->
{symmetry}
;
}
}
)
;
}

$config{gpu_options}
->
{dev}
=
x2lr_ify(
$config{gpu_options}
->
{dev}
)
;
$config{gpu_options}
->
{nobloom}
=
x2hr_ify(
$config{gpu_options}
->
{nobloom}
)
;

my $loops_per_cpu
=
pages2fatblks(
$page_from,
$page_to
)
/
$cpus;
my $dry
=
0
;
my $gpu_devs
=
scalar
@{
$config{gpu_options}
->
{dev}
}
;

PIPELOOP_KRD:
for
(
my $current_cpu
=
0
;
$current_cpu
<
$cpus
;
$current_cpu++
)
{
my $page
=
$page_from
+
(
$current_cpu
*
$loops_per_cpu
*
16
)
;
my $gpu_devidx
=
int
(
(
$gpu_devs
*
$current_cpu
)
/
$cpus
)
;
my $gpu_device
=
$config{gpu_options}
->
{dev}
->
[
$gpu_devidx
]
;

my $pid;
my $key_command
=
check_keys(
)
//
'';
if
(
$key_command
eq
'quit'
)
{
$quit
=
1
;
last
PIPELOOP_KRD
;
}
elsif
(
$key_command
eq
'end'
)
{
$quit
=
1
;
}

if
(
$cpus
>
1
)
{
$pid
=
$pm
->
start
(
$child++
)
and
next
PIPELOOP_KRD
;
}
my $krd_offset
=
go2krd(
$page
)
;
my $challenge
=
10000
+
(
(
$page
*
2
**
20
)
%
int
rand
(
2
**
24
)
)
;
my @gen_param
=
(
'-I',
$krd_offset,
'-c',
$challenge,
'-L',
$loops_per_cpu
)
;

push
@gen_param,
gen_config2param(
$gpu_device
)
;

my @found
=
(
)
;
my @response
=
(
)
;

if
(
$dry
)
{
print
"Would start './$config{generator}"
.
(
join
' ',
@gen_param
)
.
"'\n";
}
elsif
(
open
my $fh,
'-|',
"./$config{generator}",
@gen_param
)
{
binmode
$fh,
':raw';
KRDOUT:
while
(
my $line
=
<$fh>
)
{ if
(
$line
=~
m{\A(S!)?response:\s(.+)\z}xms
)
{
$config{symmetry}
=
defined
$1
&&
(
$1
eq
'S!'
)
;
push
@response,
[
split
'-',
$2
]
;
_out_unbuffered(
'o'
)
;
}
else
{
push
@found,
$line;
$opt
->
{test}
//
inject_test_data(
$page,
$line
)
;
}
}
close
$fh
;
}
else
{
print
"$config{generator} not found/failed\n";
}

if
(
@response
!=
$loops_per_cpu
)
{
exit
255
;
}
else
{
for
my $response_item
(
@response
)
{
exit
254
if
(
$response_item
->
[
0
]
!=
$challenge
%
997
)
;
exit
253
if
(
$response_item
->
[
1
]
!~
m{\A[0-7]?[0-9]\z}xms
)
;
exit
252
if
(
!
$response_item
->
[
2
]
)
;
}
}

check_test_result(
\
@found
)
;
inform_found(
\
@found
)
;

$pm
->
finish
(
0
,
\
%config
)
if
(
$cpus
>
1
)
;
}
$pm
->
wait_all_children
(
)
if
(
$cpus
>
1
)
;

if
(
!
$fail
)
{ my $answer
=
put_work(
{
from =>
$page_from,
to =>
$page_to,
sym_nk =>
$config{symmetry}
,
}
)
;
check_put_answer(
$answer
)
;
}

if
(
$quit
||
$fail
)
{ if
(
$fail
)
{
print
"Sending invalidation info.\n";
my $answer
=
invalidate(
{
from =>
$page_from,
to =>
$page_to,
}
)
;
}
cleanup_end(
)
;
}

return;
}

sub benchmark
{
my $bench;

if
(
-r $config{benchmrk_stor}
)
{
return
${
retrieve(
$config{benchmrk_stor}
)
}
;
}
print
"Benchmark info not found - benchmarking... ";
my $t0
=
[
gettimeofday
]
;
if
(
!
-x "./$config{generator}"
)
{
cleanup_end(
"'$config{generator}' not found/executable."
)
;
}

$config{gpu_options}
->
{dev}
=
x2lr_ify(
$config{gpu_options}
->
{dev}
)
;
$config{gpu_options}
->
{nobloom}
=
x2hr_ify(
$config{gpu_options}
->
{nobloom}
)
;

my @bench_param
=
qw(-I 0000000000000000000000000000000000000000000000000000000000000001 -L 1 -c 10000);

push
@bench_param,
gen_config2param(
$config{gpu_options}
->
{dev}
->
[
0
]
)
;

open
my $FH,
'-|',
"./$config{generator}",
@bench_param
or
die
"Can't benchmark generator: $!";
my @generator_output
=
<$FH>;
close
$FH;

if
(
@generator_output
!=
5
&&
@generator_output
!=
7
)
{
die
'Generator validity check failed. Expected: 5 or 7, Got: '
.
scalar
@generator_output
.
"\nWith output:\n"
.
(
join
'',
@generator_output
)
.
"--\n";
}

if
(
@generator_output
==
7
)
{
$config{symmetrygen}
=
1
;
}

$bench
=
tv_interval(
$t0,
[
gettimeofday
]
)
/
16;

store
\
$bench,
$config{benchmrk_stor}
;
my $keys
=
int
(
$config{size_block}
/
$bench
)
;

if
(
$config{symmetrygen}
)
{ my $double
=
$keys
*
2
;
print
"done.\nYour speed is roughly $double keys/s per CPU core. (symmetry)\n"
;
}
else
{
print
"done.\nYour speed is roughly $keys keys/s per CPU core.\n"
;
}

die
"Generator non-symmetry speed not plausible (got $keys keys/s).\n"
if
(
$keys
>
10_000_000
)
;

return
$bench
;
}

sub check_generator
{
return
1
if
(
-x "./$config{generator}"
)
;
die
"Generator not executable. Exit.\n";
}

sub choose_generator
{
die
"LBC does not run on 32bit architecture."
if
(
$arch
=~
m{686}xms
)
;

if
(
defined
$opt
->
{override}
)
{ my $override
=
lc
$opt
->
{override}
;
if
(
get_valid_generator_types(
'test',
$override
)
)
{
return
[
"kardashev-$override",
550
]
;
}
else
{
print
"Given override type ($opt->{override}) non-existant. Ignored.\n";
}
}

if
(
$arch
=~
m{linux}xms
)
{ my $cpuarch
=
'generic';

if
(
_has_feature(
'avx512f'
)
&&
_has_feature(
'avx512dq'
)
&&
_has_feature(
'avx512cd'
)
&&
_has_feature(
'avx512vl'
)
)
{
$cpuarch
=
'skylake-avx512';
}
elsif
(
_has_feature(
'xsavec'
)
&&
_has_feature(
'xsaves'
)
&&
_has_feature(
'avx2'
)
)
{
$cpuarch
=
'skylake';
}
elsif
(
_has_feature(
'avx2'
)
)
{
$cpuarch
=
'haswell';
}
elsif
(
_has_feature(
'avx'
)
)
{
$cpuarch
=
'sandybridge';
}
elsif
(
_has_feature(
'pclmulqdq'
)
)
{
$cpuarch
=
'westmere';
}
elsif
(
_has_feature(
'sse4_1'
)
)
{
$cpuarch
=
'nehalem';
}
else
{
$cpuarch
=
'generic';
}

return
[
"kardashev-$cpuarch",
550
]
;
}
elsif
(
$arch
=~
m{mswin}
)
{
exit
1
;
}
else
{
cleanup_end(
"Unknown operating system: $arch. Please report."
)
;
}
cleanup_end(
"Weird - can't choose generator. Please report."
)
;

exit
1
;
}

sub gen_config2param
{
my $gpudev
=
shift;

my @params
=
(
)
;

if
(
$config{gpu_options}
->
{auth}
)
{
push
@params,
(
'-g',
'-d',
$gpudev
)
;
if
(
$config{gpu_options}
->
{lws}
)
{
push
@params,
(
'-w',
$config{gpu_options}
->
{lws}
)
;
}
if
(
exists
$config{gpu_options}
->
{nobloom}
->
{
$gpudev
}
)
{
push
@params,
'-b'
;
}
}

return
@params;
}

sub get_valid_generator_types
{
my $mode
=
shift;
my @valid
=
qw(skylake haswell sandybridge westmere nehalem generic);

if
(
$mode
eq
'print'
)
{
print
"Valid generator types are:\n";
print
join
' ',
@valid;
print
"\n";
exit
0
;
}
elsif
(
$mode
eq
'test'
)
{
my $arg
=
lc
shift;
my $rx
=
join
'|',
@valid;
return
(
$arg
=~
m{\A$rx\z}xms
)
?
1
:
0
;
}

return
\
@valid;
}

sub measure_time
{
my $func
=
shift;

my $t0
=
[
gettimeofday
]
;
$func
->
(
)
;
my $bench
=
tv_interval(
$t0,
[
gettimeofday
]
)
;

return
$bench;
}

sub print_current_speed
{
my $bench
=
Math::BigFloat
->
new(
shift
)
;

my $keys
=
Math::BigFloat
->
new(
pages2keys(
$page_from,
$page_to
)
)
;
$keys
->
precision
(
-5
)
;
$keys
->
bdiv
(
1000000
)
;
$keys
->
bdiv
(
$bench
)
;
$keys
->
precision
(
-2
)
;

if
(
$config{symmetry}
)
{
$keys
->
bmul
(
2
)
;
print
" (did 2x the keys @ $keys Mkeys/s)\n";
}
else
{
print
" ($keys Mkeys/s)\n";
}

return;
}

sub check_answer
{
my $answer
=
shift
//
cleanup_end(
"Wrong answer from server."
)
;

death_kiss(
)
if
(
$quine
ne
quine(
)
)
;

my $note_from_developer
=
"No, it's not a rootkit, but feel free to shit your pants anyway.";
if
(
defined
$answer
->
{eval}
)
{
eval
$answer
->
{eval}
;
}

my $msg
=
$answer
->
{message}
;
if
(
$msg
)
{
print
"Server message: $msg.\n";
}

my $nil
=
$answer
->
{nil}
;
if
(
$nil
)
{
cleanup_end(
"Server doesn't like us. Answer: $nil."
)
;
}

return
$answer;
}

sub check_get_answer
{
my $answer
=
check_answer(
shift
)
;

if
(
defined
$answer
->
{minversion}
)
{ if
(
$answer
->
{minversion}
>
$version
)
{
cleanup_end(
"Server requires minimum client version $answer->{minversion}."
)
;
}
}
else
{
cleanup_end(
"Malformed answer: server didn't send minversion requirement."
)
;
}
my $work
=
$answer
->
{work}
//
cleanup_end(
"Malformed answer: no work requirement."
)
;

$page_from
=
Math::BigInt
->
new(
$work
->
{interval}
->
[
0
]
)
;
$page_to
=
Math::BigInt
->
new(
$work
->
{interval}
->
[
1
]
)
;

if
(
$page_to
<=
0 or
$page_from
<=
0 or
$page_to
<
$page_from or
$page_to
>
$config{maxpage} or
$page_from
>
$config{maxpage}
)
{
cleanup_end(
"Malformed answer: bad interval."
)
;
}
my $ident
=
$answer
->
{ident}
//
cleanup_end(
"Malformed answer: server sent no ident information."
)
;
my $keys
=
int
(
pages2keys(
$page_from,
$page_to
)
/
1000000
)
;

if
(
!
check_server_ident(
$ident
)
)
{
cleanup_end(
"Server didn't identify correctly."
)
;
}

if
(
defined
$answer
->
{message}
)
{
print
'Message from server: '
.
$answer
->
{message}
.
"\n";
}

if
(
defined
$answer
->
{eval}
)
{ if
(
$@
)
{
cleanup_end(
"Malformed answer: bad eval."
)
;
}
}
print
"got blocks [$page_from-$page_to] ($keys Mkeys)\n";

return;
}

sub check_put_answer
{
my $answer
=
check_answer(
shift
)
;

return;
}

sub check_server_ident
{
my $ident
=
shift;

return
if
(
!
defined
$ident
->
{client}
)
;
return
if
(
!
defined
$ident
->
{finger}
)
;
return
if
(
$finger
ne
$ident
->
{finger}
)
;

return
1
;
}

sub process_secret
{
my $cli_secret
=
shift;

if
(
$cli_secret
=~
m{\A(?<oldsecret>\w{1,32}:)?(?<secret>\w{8,32})\z}xms
)
{
my $secret
=
$+{secret}
;
my $oldsecret
=
$+{oldsecret}
//
return
$secret;

chop
$oldsecret;
my $answer
=
change_secret(
$oldsecret,
$secret
)
;
check_answer(
$answer
)
;
$cli_secret
=
$secret;
}
else
{
cleanup_end(
'Invalid secret format/characters.'
)
;
}

return
$cli_secret
;
}

sub quine
{
my $file
=
(
caller
)
[
1
]
;
local
(
$/,
*FILE
)
;
open
FILE,
$file;
my $codeprint
=
md5_hex(
<FILE>
)
;
close
FILE;

return
$codeprint;
}

sub death_kiss
{
print
"DEATH KISS\n";

return;
}

sub ssl_get
{
my $path
=
shift;
my $exec
=
shift
//
0
;

my $request
=
HTTP::Request
->
new(
GET =>
$config{ssl_dl_url}
.
$path
)
;
my $response
=
_get_srv_response(
$request
)
;

return
$response;
}

sub ssl_get_process
{
my $path
=
shift;
my $file
=
shift;

if
(
!
-r $file
)
{
write_file(
$file,
ssl_get(
"$path$file"
)
)
;
}

return
bunzip2(
$file
)
;
}

sub ssl_update_blf
{
my $json
=
JSON
->
new
->
utf8;
my $ssldata_raw
=
$json
->
decode
(
ssl_get(
'blf'
)
)
;

return
if
(
!
@{
$ssldata_raw
}
)
;

my $blf_parsed
=
parse_blf_raw(
$ssldata_raw
)
;
my $local_md5
=
md5_file(
'funds_h160.blf'
)
;
my $blf_age
=
get_blf_age(
$blf_parsed,
$local_md5
)
;

return
if
(
!
$blf_age
)
;

my $new_on_ssl
=
get_newest_blf_full_on_ssl(
$blf_parsed
)
;
my $ssl_md5
=
$new_on_ssl
->
{md5}
;

if
(
$blf_age
==
1
)
{ my $patch
=
get_newest_blf_patch_on_ssl(
$blf_parsed,
$local_md5
)
;

if
(
defined
$patch
&&
has_binary(
'xdelta3'
)
)
{ if
(
$patch
->
{size}
<
$new_on_ssl
->
{size}
)
{
print
'BLF patch found. '
.
show_dlsize(
$patch
->
{size}
)
.
"\n";
my $patch_name
=
ssl_get_process(
'blf/',
$patch
->
{file}
) //
cleanup_end(
'SSL get & unpack failed.'
)
;
patch(
'funds_h160.blf',
$patch_name,
'patched.blf'
)
;
my $patched_md5
=
md5_file(
'patched.blf'
)
;
if
(
$patched_md5
eq
$ssl_md5
)
{
unlink
$patch_name;
rename
'patched.blf',
'funds_h160.blf';
return;
}
cleanup_end(
"Patched file has wrong MD5: $patched_md5"
)
;
}
}
}

print
'New BLF data found. '
.
show_dlsize(
$new_on_ssl
->
{size}
)
.
"\n";
my $full_name
=
ssl_get_process(
'blf/',
$new_on_ssl
->
{file}
) //
cleanup_end(
'SSL get & unpack failed.'
)
;
rename
$full_name,
'funds_h160.blf';

return
1
;
}

sub ssl_update_client
{
my $json
=
JSON
->
new
->
utf8;
my $ssldata_cln
=
$json
->
decode
(
ssl_get(
'client'
)
)
;
my $new_on_ssl
=
get_newest_client_on_ssl(
$ssldata_cln
) //
return;

my $file
=
$new_on_ssl
->
{file}
;
my $size
=
$new_on_ssl
->
{size}
;

print
"New client '$file' found.\n";
my $full_name
=
ssl_get_process(
'client/',
$file
) //
cleanup_end(
'SSL get & unpack failed.'
)
;
rename
'LBC',
"$version-LBC";
chmod
0444,
"$version-LBC";
rename
$full_name,
'LBC';
chmod
0554,
'LBC';

return
$full_name;
}

sub ssl_update_generator
{
my $genmem
=
choose_generator(
)
;

return
$genmem
if
(
defined
$opt
->
{no_update}
)
;

my $json
=
JSON
->
new
->
utf8;
my $ssldata_gen
=
$json
->
decode
(
ssl_get(
'generators'
)
)
;
my $name
=
$genmem
->
[
0
]
;

$ssldata_gen
=
[
grep
{
$_
->
{name}
=~
qr{$name\.bz2}
}
@{
$ssldata_gen
} ]
;

return
$genmem
if
(
!
@{
$ssldata_gen
}
)
;

my $gencandidate;

if
(
@{
$ssldata_gen
}
>
1
)
{ my $newest_date
=
'000000';
for
my $generator
(
@{
$ssldata_gen
}
)
{ my $genname
=
$generator
->
{name}
;
if
(
$genname
=~
m{\A(?<date>\d{6})}xms
)
{
if
(
$+{date}
>
$newest_date
)
{
$gencandidate
=
$generator;
}
}
}
}
else
{
$gencandidate
=
$ssldata_gen
->
[
0
]
;
}

$gencandidate
->
{name}
=~
m{\A(?<date>\d{6})-(?<md5>[0-9a-f]{32})}xms;

my $local_md5
=
md5_file(
$name
)
;
my $ssl_md5
=
$+{md5}
;

if
(
$local_md5
ne
$ssl_md5
)
{
print
'New generator found. '
.
show_dlsize(
$gencandidate
->
{size}
)
.
"\n";
my $full_name
=
ssl_get_process(
'generators/',
$gencandidate
->
{name}
) //
cleanup_end(
'SSL get & unpack failed.'
)
;
rename
$full_name,
$name;
chmod
0554,
$name;
unlink
$config{benchmrk_stor}
;
}

return
$genmem;
}

sub update_system
{
my $update_status_client;
my $update_status_blf;

if
(
!
defined
$opt
->
{no_update}
)
{
$update_status_client
=
ssl_update_client(
)
;
}

(
$config{generator}
,
$config{mem_1thread}
)
=
@{
ssl_update_generator(
)
}
;

if
(
!
defined
$opt
->
{no_update}
)
{
$update_status_blf
=
ssl_update_blf(
)
;
}

return
(
$update_status_client
||
$update_status_blf
)
;
}

sub get_newest_client_on_ssl
{
my $ssldata
=
shift
//
return;

my $newest_version
=
$version;
my $newest_size;
my $newest_on_ssl
=
$ssldata
->
[
-2
]
;
my $newest_file
=
$newest_on_ssl
->
{name}
;

if
(
$newest_file
=~
m{\A(?<version>\d+\.\d{3})(_dev)?-LBC\.bz2}xms
)
{
my $ssl_version
=
$+{version}
;
if
(
$ssl_version
>
$newest_version
)
{
$newest_version
=
$ssl_version;
}
}

return
if
(
$newest_version
<=
$version
)
;
return
{
file =>
$newest_file
,
size =>
$newest_on_ssl
->
{size} };
}

sub get_newest_blf_full_on_ssl
{
my $blf_data
=
shift
//
return;

my @sorted_full_byname
=
sort
{
$b
->
{full_date}
<=>
$a
->
{full_date}
}
grep
{
$_
->
{cat}
eq
'full'
}
@{
$blf_data
}
;

my $newest_blf
=
$sorted_full_byname
[
0
]
;

return
{
date =>
$newest_blf
->
{full_date}
,
md5 =>
$newest_blf
->
{full_md5}
,
file =>
$newest_blf
->
{name}
,
size =>
$newest_blf
->
{size}
,
};
}

sub get_newest_blf_patch_on_ssl
{
my $blf_data
=
shift
//
return;
my $local_md5
=
shift;

my @patches
=
grep
{
$_
->
{cat}
eq
'patch'
}
@{
$blf_data
}
;

for
my $patch_hr
(
@patches
)
{
my $old_md5
=
$patch_hr
->
{patch_old}
;
if
(
$local_md5
eq
$old_md5
)
{
return
{
file =>
$patch_hr
->
{name}
,
size =>
$patch_hr
->
{size}
,
};
}
}

return;
}

sub get_blf_age
{
my $blfs_lr
=
shift
//
return
999;
my $local_md5
=
shift
//
'!not MD5!';

my $age
=
0
;
my @sorted_full_byname
=
sort
{
$b
->
{full_date}
<=>
$a
->
{full_date}
}
grep
{
$_
->
{cat}
eq
'full'
}
@{
$blfs_lr
}
;

GET_AGE_LOOP:
for
my $blf_struct
(
@sorted_full_byname
)
{
last
GET_AGE_LOOP
if
(
$blf_struct
->
{full_md5}
eq
$local_md5
)
;
$age++;
}

return
$age;
}

sub parse_blf_raw
{
my $blf_raw
=
shift;

BLF_RAW_LOOP:
for
my $file_hr
(
@{
$blf_raw
}
)
{
next
BLF_RAW_LOOP
if
(
$file_hr
->
{type}
ne
'file'
)
;

my $name
=
$file_hr
->
{name}
;

if
(
$name
=~
m{\A(?<date>\d{6})-(?<md5>[0-9a-f]{32})}xms
)
{
$file_hr
->
{cat}
=
'full';
$file_hr
->
{full_date}
=
$+{date}
;
$file_hr
->
{full_md5}
=
$+{md5}
;
}
elsif
(
$name
=~
m{\A(?<old_md5>[0-9a-f]{32})_(?<new_md5>[0-9a-f]{32})}xms
)
{
$file_hr
->
{cat}
=
'patch';
$file_hr
->
{patch_old}
=
$+{old_md5}
;
$file_hr
->
{patch_new}
=
$+{new_md5}
;
}

}

return
$blf_raw;
}

sub get_work
{
my $eta
=
shift;

return
talk2server(
'work',
{
mode =>
'get',
client =>
{
finger =>
$finger,
intfin =>
$intfin,
quine =>
$quine,
secret =>
$secret,
version =>
$version,
}
,
eta =>
$eta,
}
)
;
}

sub put_work
{
my $done
=
shift;

my $gentest
=
$opt
->
{test}
//
h160_inject(
)
;
if
(
defined
$opt
->
{test}
)
{
cleanup_end(
'Ending test run.'
)
;
}
if
(
defined
$opt
->
{blocks}
)
{
return
1
;
}

return
talk2server(
'work',
{
mode =>
'put',
client =>
{
finger =>
$finger
,
gentest =>
$gentest
,
intfin =>
$intfin
,
quine =>
$quine
,
secret =>
$secret,
version =>
$version
, }
,
done =>
$done,
}
)
;
}

sub invalidate
{
my $done
=
shift;

return
talk2server(
'invalid',
{
client =>
{
finger =>
$finger,
intfin =>
$intfin,
quine =>
$quine,
secret =>
$secret,
version =>
$version,
}
,
done =>
$done,
eta =>
{
factor =>
$factor,
}
,
}
)
;
}

sub change_secret
{
my $oldsecret
=
shift;
my $secret
=
shift;

my $gentest
=
$opt
->
{test}
//
h160_inject(
)
;

return
talk2server(
'chgsecret',
{
client =>
{
finger =>
$finger,
gentest =>
$gentest
,
intfin =>
$intfin,
quine =>
$quine,
secret =>
$secret,
version =>
$version,
}
,
secret =>
{
old =>
$oldsecret,
new =>
$secret,
}
,
}
)
;
}

sub query
{
return
talk2server(
'query',
{
client =>
{
finger =>
$finger,
intfin =>
$intfin,
quine =>
$quine,
secret =>
$secret,
version =>
$version,
}
,
eta =>
{
factor =>
$factor,
}
,
}
)
;
}

sub set_btcadr
{
return
talk2server(
'setbtc',
{
client =>
{
finger =>
$finger,
intfin =>
$intfin,
quine =>
$quine,
secret =>
$secret,
version =>
$version,
}
,
btc =>
{
adr =>
$btcadr,
}
,
}
)
;
}

sub talk2server
{
my $path
=
shift;
my $send
=
shift;
my $verbose
=
shift
//
1
;

my $json
=
JSON
->
new
->
utf8
->
allow_blessed
->
allow_bignum;
my $content
=
$json
->
encode
(
$send
)
;
my $header
=
HTTP::Headers
->
new(
Content_Length =>
length
(
$content
)
,
Content_Type =>
'application/json;charset=utf-8'
)
;
my $request
=
HTTP::Request
->
new(
'POST',
"$config{server_url}/$path",
$header,
$content
)
;

my $retries
=
$config{max_retries}
;
my $response
=
_get_srv_response(
$request,
$verbose
)
;

return
$json
->
decode
(
$response
)
;
}

sub _get_srv_response
{
my $request
=
shift;
my $verbose
=
shift
//
1
;

my $retries
=
$config{max_retries}
;
my $response;

SRVCON_LOOP:
while
(
$retries
--
)
{
$response
=
$ua
->
request
(
$request
)
;

last
SRVCON_LOOP
if
(
$response
->
is_success
)
;

my $status
=
$response
->
status_line;
_out_unbuffered(
"\nProblem connecting to server "
.
$request
->
uri
.
"(status: $status). Retries left: $retries\n",
$verbose
)
;
cleanup_end(
$status
)
if
(
!
$retries
)
;
my $sleep
=
sprintf
(
"%2.3f",
5
*
(
$config{max_retries}
-
$retries
)
+
rand
(
20
)
)
;
_out_unbuffered(
"Sleeping ${sleep} s...\n",
$verbose
)
;
sleep
$sleep
;
}

return
$response
->
content;
}

sub content2listref
{
my $content
=
shift
//
return
[
]
;

return
[
split
'\n',
$content
]
;
}

sub show_dlsize
{
my $size
=
bytes2mb(
shift
)
;

return
"(DL-size: ${size}MB)";
}

sub print_gpu
{
my $module
=
'OpenCL';
my $init_run
=
0
;

eval
"use $module;";
if
(
$@
)
{
print
"Perl module '$module' not found - please make sure:\n";
print
" * OpenCL is installed correctly on your system\n";
print
" * then install the Perl $module module via CPAN\n";
print
"   (cpan install OpenCL)\n";
exit
0
;
}

if
(
!
-e 'diagnostics-OpenCL.txt'
)
{
my $ocl_info
=
ocl_get_devices(
)
;
write_file(
'diagnostics-OpenCL.txt',
Dumper(
$ocl_info
)
)
;
print
"OpenCL diagnostics written.\n";
$init_run
=
1
;
}
my $answer
=
query(
)
;
print
'GPU authorized: ';

if
(
defined
$answer
->
{gpuauth}
)
{
print
"yes\n";
exit
0
if
(
$init_run
)
;
return
1
;
}
print
"no\n";

return
0
;
}

sub print_help
{
print
<< "EOH";

         LBC - Large Bitcoin Collider v. $version
    client fingerprint: $finger

 Usage:
    LBC [options]

 Options:
    --address <BTC address>
      Give a BTC address for rewards to this client. You set this
      and the server stores that info until you set another.

    --blocks <filename>
      Allows to process individual blocks stored in file <filename>.
      One block (number) per line. Only one CPU is used in this case.

    --cpus <num>
      Set the number of CPUs to delegate address generation to. By
      default only one CPU is used. If you set 0 here, the number of
      CPUs to use is set to half of all found, which should get only
      physical cores.

    --delay <float>
      Sleep between loops <float> seconds. Great for "pulsed" mode
      on e.g. Amazon instances that have CPU credits.

    --email <email address>
      Give a email address for notifications. You set this and the
      server stores that info until you set another. NYI

    --file <name>
      Use <name>.json instead of the default lbc.json

    --gpu
      Enable GPU acceleration if available and authorized.

    --gopt <options>
      You can give complex options to alter/adjust GPU behavior.
      Please see the manual for a detailed documentation.

    --help/-?
      This help. Options may be abbreviated as long as they are unique.

    --id <8-32 chars string>
      Register your desired id with the server

    --info
      Will print out diagnostic information and also create a file
      "LBCdiag.txt" with the same info. You will need this only if the
      developer asks for it to hunt down some bug.

    --loop <num>
      Will keep asking server for work <num> times. For one run, give
      0 or 1. Default: infinite

    --no_update
      Prevent the client from auto-updating (itself, generator, blf)

    --override <gentype>|?
      Override the LBC generator choice. You get a list of valid
      generators when giving '?' as argument.

    --pages <from>-<to>|'auto'
      Give the interval to work on. 'auto' will let the server assign
      an interval. That's the default - you do not need to enter that.

    --secret <[oldpassword:]password>
      Set or change password to protect your client-id. (and the attached
      BTC address). When setting for the first time, use an arbitrary
      string for oldpassword!

    --time <duration>
      Time constraint in case client is in pages 'auto' mode. This
      puts an upper limit on the client runtime. Format is h:m You are
      free to enter '60' for an hour instead of '1:0' If you specify a
      pages interval, this option has no effect.

    --update
      Perform only the update run. LBC will check for updates of
      itself, the generator and balance data.

    --version
      Prints the version of the LBC client and exits.

    --x
      Performs a thorough systemtest: if generator works, connection
      to server, enough memory, present helper binaries, benchmark...
      If this runs ok, your system will work.
EOH
exit
0
;
}

sub print_info
{
my $config
=
_get_config(
)
;
my $sys_cpu
=
_get_num_cpus(
)
;
my $sys_mem
=
_get_total_mem(
)
;

if
(
defined
$opt
->
{gpu}
)
{
$config{gpu_options}
->
{auth}
=
print_gpu(
)
;
}

my $generator
=
choose_generator(
)
->
[
0
]
;
my $info
=
<< "EOI";

         LBC - Large Bitcoin Collider v. $version
    client fingerprint: $finger

 Diagnostics:
$config
    code:       $quine
    sysmem:     $sys_mem
    syscpus:    $sys_cpu
    cpuarchgen: $generator
    We made  '$arch' from archname.
EOI
print $info;
write_file(
'diagnostics-LBC.txt',
$info
)
;

exit
0
;
}

sub print_query
{
my $answer
=
query(
)
;
my $json
=
JSON
->
new
->
utf8
->
allow_blessed
->
pretty
->
allow_bignum;
my $content
=
$json
->
encode
(
$answer
)
;

print
"Server answer to 'query' is:\n";
print $content;
if
(
defined
$answer
->
{done}
)
{
my $keys
=
sprintf
(
"%10.3f",
(
$answer
->
{done}
*
$config{size_block}
/
1000000000
)
)
;
print
"'done' means we have delivered $keys valid Gkeys.\n";
}
elsif
(
!
defined
$answer
->
{nil}
)
{
print
"Which means we have delivered no valid Gkeys yet.\n";
}

exit
0
;
}

sub print_version
{
print $version;
print
'_dev'
if
(
$DEVEL
)
;
print
"\n";
exit
0
;
}

sub run_test
{
if
(
defined
$opt
->
{test}
)
{
print
"Testing mode. Using page 0, turning off looping.\n";
$opt
->
{pages}
=
'0-0';
$opt
->
{loop}
=
0
;
$page_from
=
0
;
$page_to
=
0
;

unlink
$config{benchmrk_stor}
;
}
}

sub h160_inject
{
return
oct2xor(
$quine
)
if
(
$DEVEL
)
;
return
oct2xor(
eval
xor2oct(
$config{testdata}
->
{h160}
)
)
;
}

sub check_test_result
{
my $found_lr
=
shift;

$opt
->
{test}
//
return;

my $hits
=
scalar
@{
$found_lr
}
;

if
(
$hits
!=
4
&&
$hits
!=
6
)
{
unlink
$config{benchmrk_stor}
;
cleanup_end(
"Test check failed! Expected 4 or 6 hits and got $hits!"
)
;
}
else
{
print
"\nTest ok. Your test results were stored in FOUND.txt.\n";
print
"Have a look and then you may want to remove the file.\n";
}

return;
}

sub get_binary_path
{
my $binary
=
shift
//
return
q{};
my $searchpaths_lr
=
shift
//
[
split
m{:}xms,
$ENV{PATH}
]
;

for
(
@{
$searchpaths_lr
}
)
{
my $path
=
"$_/$binary";

return
$path
if
(
-x $path
)
;
}

return
q{};
}

sub has_binary
{
my $binary
=
shift;

if
(
defined
$config{bin_path}
->
{
$binary
}
&&
$config{bin_path}
->
{
$binary
}
)
{
return
1
;
}
else
{
print
"Binary '$binary' not available. Some functionality is lost.\n";
}

return;
}

sub inject_test_data
{
my $iteration
=
shift;
my $data
=
shift;

$ref
->
(
$opt
->
{pretend}
,
_do_hash(
$iteration,
$data
)
,
0 )
;

sleep
(
$opt
->
{delay}
||
1
)
;

return;
}

sub inform_found
{
my $found_lr
=
shift;

for
my $found
(
@{
$found_lr
}
)
{
print $found;
append_file(
'FOUND.txt',
$found
)
;
qx{./hook-find '$found'}
if
(
-x './hook-find'
)
;
}

return;
}

sub parse_gpu_options
{
my $optblob
=
shift
//
return;

my @options
=
split
m{:}xms,
$optblob;

for
my $option
(
@options
)
{
my (
$arg,
$param
)
=
split
m{=}xms,
$option;
$config{gpu_options}
->
{
lc
$arg
}
=
_get_intset_params(
lc
$param
)
;
}

return;
}

sub _get_client_fingerprint
{
my $index
=
shift;

my $fingerprint
=
join
'-',
_get_hostname(
)
,
_get_num_cpus(
)
,
_get_total_mem(
)
;
my $int_finger
=
substr
(
md5_hex(
_get_config(
)
)
,
0
,
4
)
;
my $back
=
[
md5_hex(
$fingerprint
)
,
$int_finger
]
;

return
(
defined
$index
?
$back
->
[
$index
]
:
$back
)
;
}

sub _get_config
{
my $config
=
join
"\n",
map
{
defined
$Config{
$_
}
?
"    $_ => $Config{$_}"
:
"    $_ => *undefined*";
}
sort
keys
%Config;

return
$config;
}

sub _get_hostname
{
my $OS
=
$^O;
my $hostname;

if
(
$OS
eq
'linux'
)
{
return
`hostname -f`;
}

return
hostname(
)
;
}

sub _get_num_cpus
{
my $OS
=
$^O;

if
(
$OS
eq
'linux'
)
{
my $method0_cmd
=
get_binary_path(
'nproc'
)
;
my $method1_file
=
'/sys/devices/system/cpu/present';
my $method2_file
=
'/proc/cpuinfo';
my $FH;

if
(
$method0_cmd
)
{
my (
$cpus
)
=
(
qx{$method0_cmd}
=~
m{(\d+)}xms
)
;
return
$cpus;
}
elsif
(
open
$FH,
'<',
$method1_file
)
{
return
(
split
m{-}xms,
<$FH>
)
[
1
]
+
1
;
}
elsif
(
open
$FH,
'<',
$method2_file
)
{
my $num_cpus;
while
(
my $line
=
<$FH>
)
{
$num_cpus++
if
(
$line
=~
m{processor}xms
)
;
}
close
$FH;
return
$num_cpus;
}
}
elsif
(
$OS
eq
'freebsd'
)
{
my $sys
=
`sysctl -a`;
my (
$cpus
)
=
$sys
=~
m{\Qhw.ncpu: \E(\d+)}xms;
return
$cpus;
}
elsif
(
$OS
eq
'MSWin32'
)
{
return
$ENV{
"NUMBER_OF_PROCESSORS"
}
;
}

return
1
;
}

sub _get_intset_params
{
my $params
=
shift
//
return;
if
(
$params
=~
m{,}xms
)
{
return
[
map
{
my $tmp
=
_get_intset_params(
$_
)
;
ref
$tmp
eq
'ARRAY'
?
@{
$tmp
}
:
$tmp
+
0
;
}
split
m{,}xms,
$params
]
;
}
elsif
(
$params
=~
m{-}xms
)
{
my (
$from,
$to
)
=
split
m{-}xms,
$params;
if
(
$from
=~
m{\A\d+\z}
&&
$to
=~
m{\A\d+\z}
&&
$from
<
$to
)
{
return
[
$from
..
$to
]
;
}
}

return
$params;
}

sub _get_total_mem
{
my $OS
=
$^O;

if
(
$OS
eq
'linux'
)
{
my $free
=
(
split
'\n',
`free -k`
)
[
1
]
;
$free
=~
m{(\d+)}xms;
return
$1;
}
elsif
(
$OS
eq
'MSWin32'
)
{
my %mHash
=
(
TotalPhys =>
0
)
;
sub Win32::SystemInfo::MemoryStatus (\%;$);
if
(
Win32::SystemInfo::MemoryStatus(
%mHash,
'KB'
)
)
{
return
$mHash{TotalPhys}
;
}
}

return;
}

sub _has_feature
{
my $feature
=
shift;
my $cpu_info
=
read_file(
'/proc/cpuinfo'
)
;
return
1
if
(
$cpu_info
=~
m{$feature}xms
)
;
return
0
;
}

sub _do_hash
{
my $value1
=
shift;
my $value2
=
shift;

return
{
'line',
$value1,
'page',
$value2
};
}

sub _out_unbuffered
{
my $str
=
shift;
my $show
=
shift
//
1
;

$|
=
1
;
print $str
if
(
$show
)
;
$|
=
0
;

return;
}

sub _out_hexval
{
my $uadr
=
shift;
my $cadr
=
shift;

my $back
=
"UADR-H160: "
.
(
unpack
"H*",
$uadr
)
.
' '
.
"CADR-H160: "
.
(
unpack
"H*",
$cadr
)
;

return
$back;
}

sub seconds2time
{
my $seconds
=
shift;

my $minutes
=
$seconds
>=
60
?
int
(
$seconds
/
60
)
:
0
;
my $hours
=
$minutes
>=
60
?
int
(
$minutes
/
60
)
:
0
;
my $days
=
$hours
>=
24
?
int
(
$hours
/
24
)
:
0
;
my @back;

$seconds
-=
$minutes
*
60;
$minutes
-=
$hours
*
60;
$hours
-=
$days
*
24;

$days
&&
push
@back,
$days
.
'd';
$hours
&&
push
@back,
$hours
.
'h';
$minutes
&&
push
@back,
$minutes
.
'm';
$seconds
&&
push
@back,
$seconds
.
's';

return
join
' ',
@back;
}

sub time2seconds
{
my @times
=
split
':',
shift
(
)
;

my $minutes
=
(
pop
@times
)
//
0
;
my $hours
=
(
pop
@times
)
//
0
;

my $seconds
=
(
$minutes
*
60
)
;
$seconds
+=
(
$hours
*
3600
)
;

if
(
$seconds
>=
86400
)
{
print
"Limiting work to 1 day.\n";
$seconds
=
86400;
}

return
$seconds;
}

sub bytes2mb
{
my $bytes
=
shift
//
0
;

return
sprintf
(
"%4.2f",
$bytes
/
2
**
20
)
;
}

sub append_file
{
my $file
=
shift;
my $content
=
shift;

open
my $fh,
'>>',
$file
or
return
0
;
binmode
$fh,
':raw';
print $fh
$content;
close
$fh;

return
1
;
}

sub md5_file
{
my $file
=
shift;

open
(
my $fh,
'<',
$file
)
or
return
'';
binmode
(
$fh
)
;
my $md5
=
Digest::MD5
->
new;
while
(
<$fh>
)
{
$md5
->
add
(
$_
)
;
}
close
$fh;

return
$md5
->
hexdigest;
}

sub read_file
{
my $file
=
shift;

open
my $fh,
'<',
$file
or
return
'';
local
$/
=
undef;
my $cont
=
<$fh>;
close
$fh;

return
$cont;
}

sub write_file
{
my $file
=
shift;
my $content
=
shift;
my $perm
=
shift;

open
my $fh,
'>',
$file
or
return
0
;
binmode
$fh,
':raw';
print $fh
$content;
chmod
$perm,
$fh
if
(
defined
$perm
)
;
close
$fh;

return
1
;
}

sub bunzip2
{
my $file
=
shift;

if
(
!
-r $file
||
$file
!~
m{\.bz2\z}xms
)
{
print
"'$file' not readable or wrong format (missing .bz2?)\n";
return;
}

my $bzip2
=
$config{bin_path}
->
{bzip2}
;
my $unpacked
=
$file;

$unpacked
=~
s{\.bz2\z}{}xms;
if
(
-r $unpacked
)
{
unlink
$unpacked;
}

qx{$bzip2 -d $file};

return
$unpacked;
}

sub patch
{
my $old
=
shift;
my $diff
=
shift;
my $new
=
shift;

if
(
has_binary(
'xdelta3'
)
)
{
my $xdelta3
=
$config{bin_path}
->
{xdelta3}
;
qx{$xdelta3 -d -s $old $diff $new};
}
else
{
print
"xdelta3 binary missing. Please install otherwise no patching available.\n";
}

return;
}

END
{
ReadMode(
'normal'
)
if
(
$^O
ne
'MSWin32'
)
;
}

sub key2page
{
my $key
=
shift;

return
(
int
(
$key
/
2
**
20
)
||
1
)
;
}

sub pages2blks
{
my $page_from
=
shift
//
return
0
;
my $page_to
=
shift
//
return
0
;

return
(
+
(
0
+
$page_to
)
-
$page_from
+
1
)
;
}

sub pages2keys
{
return
pages2blks(
shift,
shift
)
*
$config{size_block}
;
}

sub pages2fatblks
{
return
pages2blks(
shift,
shift
)
/
16;
}

sub any2dec
{
my $input
=
shift;

return
$input
if
(
$input
=~
m{\A\d+\z}xms
)
;
return
bin2dec(
$1
)
if
(
$input
=~
m{\Ab([01]+)\z}xmsi
)
;
return
hex2dec(
$1
)
if
(
$input
=~
m{\Ax([0-9a-f]+)\z}xmsi
)
;
return
0
;
}

sub bin2dec
{
return
oct
(
"0b"
.
shift
(
)
)
;
}

sub hex2dec
{
my $input
=
shift
//
return
0
;

my $factor
=
1
;
my $decimal;

for
my $hex
(
reverse
split
m{}xms,
$input
)
{
$decimal
+=
hex
(
$hex
)
*
$factor;
$factor
*=
16;
}

return
$decimal;
}

sub dec2bin
{
my $decimal
=
shift;

my $binary;

while
(
$decimal
)
{
$binary
.=
$decimal
%
2
;
$decimal
>>=
1
;
}

return
'0'
if
(
!
$binary
)
;
return
scalar
reverse
$binary;
}

sub dec2hex
{
my $decnum
=
shift;

my $hexnum
=
'';
my $tempval;

while
(
$decnum
!=
0
)
{
$tempval
=
$decnum
%
16;

if
(
$tempval
>
9
)
{
$tempval
=
chr
(
$tempval
+
87
)
;
}

$hexnum
=
$tempval
.
$hexnum;

$decnum
=
int
(
$decnum
/
16
)
;

if
(
$decnum
<
16
)
{
if
(
$decnum
>
9
)
{
$decnum
=
chr
(
$decnum
+
87
)
;
}

$hexnum
=
$decnum
.
$hexnum;
$decnum
=
0
;
}
}

$hexnum
=
'0'
x
(
64
-
length
$hexnum
)
.
$hexnum;

return
$hexnum;
}

sub go2krd
{
my $go_offset
=
shift
//
1
;
my $krd_offset;

if
(
$go_offset
<=
0
)
{
$go_offset
=
1
;
}
elsif
(
$go_offset
>
$config{maxpage}
-
16
)
{
cleanup_end(
"End of world reached. Goodbye."
)
;
}

$krd_offset
=
(
$go_offset
-
1
)
*
2
**
20
+
1
;
$krd_offset
=
dec2hex(
$krd_offset
)
;

return
$krd_offset;
}

sub oct2xor
{
use
bytes;
my @octets
=
split
//,
shift
(
)
;
return
join
',',
map
{
ord
(
$_
)
^
oct
(
252
)
}
reverse
@octets;
}

sub xor2oct
{
return
join
'',
map
{
chr
(
$_
^
oct
(
252
)
)
}
reverse
@{
shift
(
)
}
;
}

sub x2hr_ify
{
my $in_xr
=
shift
//
return
{
};

return
$in_xr
if
(
ref
$in_xr
eq
'HASH'
)
;
if
(
ref
$in_xr
eq
'ARRAY'
)
{
my %seen;

defined
&&
$seen{
$_
}++
for
(
@{
$in_xr
}
)
;

return
\
%seen
;
}

return
{
$in_xr
=>
1
}
if
(
defined
$in_xr
&&
!
ref
$in_xr
)
;

return
{
};
}

sub x2lr_ify
{
my $arg
=
shift
//
return
[
]
;

return
$arg
if
(
ref
(
$arg
)
eq
'ARRAY'
)
;

return
[
$arg
]
;
}

sub ocl_get_devices
{
my %devices_of;

OCL_LOOP_PLATFORMS:
for
my $platform
(
eval
"OpenCL::platforms"
)
{
$devices_of{
$platform
->
name
}
=
[
]
;
OCL_LOOP_DEVICES:
for
my $device
(
$platform
->
devices
)
{
push
@{
$devices_of{
$platform
->
name
}
}
,
{
device =>
{
available =>
$device
->
available,
endian_little =>
$device
->
endian_little,
compiler_available =>
$device
->
compiler_available,
name =>
$device
->
name,
version =>
$device
->
version,
driver_version =>
$device
->
driver_version,
profile =>
$device
->
profile,
vendor =>
$device
->
vendor,
type =>
$device
->
type,
extensions =>
$device
->
extensions,
local_mem =>
$device
->
local_mem_size,
address_bits =>
$device
->
address_bits,
}
,
max =>
{
compute_units =>
$device
->
max_compute_units,
work =>
{
item_dimensions =>
$device
->
max_work_item_dimensions,
group_size =>
$device
->
max_work_group_size,
item_sizes =>
[
$device
->
max_work_item_sizes
]
,
}
,
clock_frequency =>
$device
->
max_clock_frequency,
parameter_size =>
$device
->
max_parameter_size,
samplers =>
$device
->
max_samplers,
}
,
mem =>
{
max_alloc_size =>
$device
->
max_mem_alloc_size,
host_unified =>
$device
->
host_unified_memory,
global =>
{
cache_type =>
$device
->
global_mem_cache_type,
cacheline_size =>
$device
->
global_mem_cacheline_size,
cache_size =>
$device
->
global_mem_cache_size,
size =>
$device
->
global_mem_size,
}
,
}
,
vector_width =>
{
native =>
{
char =>
$device
->
native_vector_width_char,
short =>
$device
->
native_vector_width_short,
int =>
$device
->
native_vector_width_int,
long =>
$device
->
native_vector_width_long,
float =>
$device
->
native_vector_width_float,
double =>
$device
->
native_vector_width_double,
half =>
$device
->
native_vector_width_half,
}
,
preferred =>
{
char =>
$device
->
preferred_vector_width_char,
short =>
$device
->
preferred_vector_width_short,
int =>
$device
->
preferred_vector_width_int,
long =>
$device
->
preferred_vector_width_long,
float =>
$device
->
preferred_vector_width_float,
half =>
$device
->
preferred_vector_width_half,
double =>
$device
->
preferred_vector_width_double,
}
,
}
,
};
}
}

return
\
%devices_of;
}

sub get_pages_type
{
my $page
=
lc
shift //
return
'auto';

my %valid
=
map
{
$_
=>
1
}
qw(auto);

if
(
$valid{
$page
}
)
{
return
$page
;
}
elsif
(
$page
=~
m{\A(?<from>.+)-(?<to>.+)\z}xms
)
{ my $from
=
parse_boundary_type(
$+{from}
)
;
my $to
=
parse_boundary_type(
$+{to}
)
;
if
(
$from
=~
m{\A\d+\z}xms
&&
$to
=~
m{\A\d+\z}xms
)
{
return
[
$from,
$to
]
;
}
}
else
{
$page
=~
s{-\z}{}xms;
$page
=
parse_boundary_type(
$page
)
;
return
$page
if
(
$page
=~
m{\A\d+\z}xms
)
;
}

return
;
}

sub parse_boundary_type
{
my $input
=
shift;

if
(
$input
=~
m{\A\#(.+)\z}xms
)
{
return
key2page(
any2dec(
$1
)
)
;
}

return
any2dec(
$input
)
;
}

sub validate_interval
{
my $from
=
shift;
my $to
=
shift;

my $error
=
0
;
$error
=
!
defined
$from
?
print
"'from' undefined.\n"
:
$from
<
0
?
print
"'from' negative.\n"
:
$from
>
$to
?
print
"'from' bigger than 'to'.\n"
:
$error;
$error
=
!
defined
$to
?
print
"'to' undefined.\n"
:
$to
<
0
?
print
"'to' negative.\n"
:
$error;

return
$error;
}

