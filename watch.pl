#!/usr/bin/perl
use warnings;
use strict;
use JSON::Parse 'parse_json';
use Term::ANSIColor qw(:constants);
my $domain=shift || usage();
my $root_url="https://$domain.campfirenow.com";
my $token=shift || gettoken();
my $room=shift || getroom();
$| = 1;


my %users;
my %entries;
my $room_url="$root_url/room/$room";

while(1)
{
	my $room_json=`curl -s -u $token:0 $room_url/transcript.json`;
	my $room_info=parse_json($room_json);
	foreach my $msg (@{$room_info->{'messages'}})
	{
		next unless $msg->{'body'};
		next if $entries{$msg->{'id'}};
		my $user=getuser($msg->{"user_id"});
		chomp(my $body=$msg->{'body'});
		if($body=~m/http.*(\.jpg|\.jpeg|\.bmp|\.gif|\.png)$/)
		{
			print BOLD, BLUE, "$user:", RESET;
			print " $body\n";
			chomp(my $md5=`echo '$body' | md5sum | awk '{print \$1}'`);
			if(! -e "/tmp/$md5")
			{
				my $cnv_cmd="convert $body jpg:- | jp2a --width=120 - > /tmp/$md5";
				system($cnv_cmd);
			}
			system "cat /tmp/$md5";
			print "\n";
		}
		else
		{
			print BOLD, BLUE, "$user:", RESET;
			print " $body\n";
		}
		$entries{$msg->{'id'}}=1;
	}
	my $count=2;
	my $txt;
	eval {
		local $SIG{ALRM} = sub {
			if (--$count) {alarm 1;}
			else {die "timeout"}
		};
		alarm 1;
		$txt=<STDIN>;
		alarm 0;
	};

	postmsg($txt) if $txt;
	$txt='';
	sleep 1;
}
sub gettoken
{
	print "email: ";
	chomp(my $ea=<STDIN>);
	print "pass: ";
	system("stty -echo");
	chomp(my $pass=<STDIN>);
	print "\n";
	system("stty echo");
	my $raw_json=`curl -s -u$ea:$pass $root_url/users/me.json`;
	my $user_json=parse_json($raw_json) or die("Couldn't parse JSON, raw json='$raw_json'\n");
	use Data::Dumper;
	return $user_json->{'user'}->{'api_auth_token'};
}
sub getroom
{
	my $rooms_json=parse_json(`curl -s -u $token:0  $root_url/rooms.json`);
	use Data::Dumper;
	my %rooms;
	my $count=1;
	foreach my $room (@{$rooms_json->{"rooms"}})
	{
		$rooms{$count}{"ID"}=$room->{'id'};
		$rooms{$count}{"name"}=$room->{'name'};
		$rooms{$count}{"topic"}=$room->{'topic'};
		$count++;
	}
	foreach my $id (sort keys %rooms)
	{
		print "$id, $rooms{$id}{'name'}   ";
		if($rooms{$id}{'topic'}){print "($rooms{$id}{'topic'})"}
		print "\n";
	}
	print "Enter room #: ";
	chomp(my $num=<STDIN>);
	print Dumper $rooms{$num};
	if(!$rooms{$num}{'ID'}){die("No room number\n");}
	return $rooms{$num}{'ID'};
}

sub postmsg
{
	my $msg=shift;
	$msg=~s/\n/&#xA;/g;
	my $url=`curl -i -H 'Content-Type: application/xml' -d "<message><type>TextMessage</type><body>$msg</body></message>" -s -u $token:0 $room_url/speak.xml`;
}


sub getuser
{
	my $uid=shift;
	return $users{$uid} if $users{$uid};
	my $user_info=parse_json(`curl -s -u $token:0 https://$domain.campfirenow.com/users/$uid.json`);
	$users{$uid}=$user_info->{'user'}->{'name'};
	return getuser($uid);
}


sub usage
{
	print "Usage: $0 <domain> [<token>]  [<room id>] 
	ex:
		perl $0 mydomain    (will prompt for username and pass)
		perl $0 mydomain myapikey (will ask for room name to join)
		perl $0 mydomain myapikey myroomid   (will join room)
	\n";
	exit();
}
