#!/usr/bin/perl
use warnings;
use strict;
use Switch;
use JSON::Parse 'parse_json';
use Term::ANSIColor qw(:constants);
use Data::Dumper;

my %users;
my %entries;
my %rooms;

my $domain=shift || usage();
my $root_url="https://$domain.campfirenow.com";
my $token=shift || get_token();
my $room=shift;
my $show_images=1;
$| = 1;

populate_rooms();
if($room)
{
	foreach my $id(keys %rooms)
	{
		print "$id,$rooms{$id}{'ID'}\n";
		if($rooms{$id}{'ID'}==$id)
		{
			watch_room($id);
		}
	}
}
else
{
	watch_room(get_room());
}

sub watch_room
{
	my $room=shift || return;
	print "Joining room $rooms{$room}{'name'}\n";
	my $room_url="$root_url/room/$rooms{$room}{'ID'}";
	while(1)
	{
		my $room_info=get_json("$room_url/transcript.json");
		foreach my $msg (@{$room_info->{'messages'}})
		{
			next unless $msg->{'body'};
			next if $entries{$msg->{'id'}};
			my $user=getuser($msg->{"user_id"});
			chomp(my $body=$msg->{'body'});
			print BOLD, BLUE, "$user:", RESET;
			print " $body\n";
			if($show_images && $body=~m/http.*(\.jpg|\.jpeg|\.bmp|\.gif|\.png)$/)
			{
				chomp(my $md5=`echo '$body' | md5sum | awk '{print \$1}'`);
				if(! -e "/tmp/$md5")
				{
					my $cnv_cmd="convert $body jpg:- | jp2a --width=120 - > /tmp/$md5";
					system($cnv_cmd);
				}
				system "cat /tmp/$md5";
				print "\n";
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
			chomp($txt=<STDIN>);
			alarm 0;
		};
		if($txt)
		{
			switch ($txt) {
				case '/quit'	{ exit() }
				case '/list'	{ print_room_list() }
				case /\/join /	{ $txt=~s/\/join\s+(\d+)$/$1/;watch_room($txt)}
				case '/join'	{ watch_room(get_room()) }
				case '/rooms'	{print_room_list()}
				case '/token'	{ print "$token\n" }
				case '/images on'	{ $show_images=1;print "Images on\n"}
				case '/images off'	{ $show_images=0;print "Images off\n"}
				case "/help"	{ print_help() }
				case '/users'	{ print_users($room) }
				else { postmsg($room_url,$txt) }
			}
			$txt='';
		}
		sleep 1;
	}
}
sub get_token
{
	print "email: ";
	chomp(my $ea=<STDIN>);
	print "pass: ";
	system("stty -echo");
	chomp(my $pass=<STDIN>);
	print "\n";
	system("stty echo");
	my $raw_json=get_json("$root_url/users/me.json");
	return $raw_json->{'user'}->{'api_auth_token'};
}
sub print_users
{
	my $id=shift;
	print "Users in $rooms{$id}{'name'}\n";
	my $room_info=get_json("$root_url/room/$rooms{$id}{'ID'}.json");
	if(!$room_info){print BOLD, RED "Error getting users\n", RESET;return}
	my $room=$room_info->{'room'};
	my @users=@{$room->{'users'}};
	foreach my $user(@users)
	{
		print "\t$user->{'name'}\n";
	}

}
sub populate_rooms
{
	print "Populating rooms\n";
	my $rooms_json=get_json("$root_url/rooms.json");
	#print Dumper $rooms_json;
	my $count=1;
	my @rooms=@{$rooms_json->{'rooms'}};
	foreach my $rm (@rooms)
	{
		$rooms{$count}{"ID"}=$rm->{'id'};
		$rooms{$count}{"name"}=$rm->{'name'};
		$rooms{$count}{"topic"}=$rm->{'topic'};
		$count++;
	}
}
sub print_room_list
{
	print "Rooms:\n";
	if(scalar(keys %rooms) < 1){populate_rooms()}
	foreach my $id (sort keys %rooms)
	{
		print "$id, $rooms{$id}{'name'}   ";
		if($rooms{$id}{'topic'}){print "($rooms{$id}{'topic'})"}
		print "\n";
	}
}
sub get_room
{
	print_room_list();
	print "Enter room #: ";
	chomp(my $num=<STDIN>);
	if($num eq '/help'){print_help();return get_room();}
	if(!$rooms{$num}{'ID'}){die("No room number\n");}
	return $num;
}

sub postmsg
{
	my $room_url=shift;
	my $msg=shift || die("No message passed to postmsg");
	$msg=~s/\n/&#xA;/g;
	my $url=`curl -i -H 'Content-Type: application/xml' -d "<message><type>TextMessage</type><body>$msg</body></message>" -s -u $token:0 $room_url/speak.xml`;
}

sub getuser
{
	my $uid=shift;
	return $users{$uid} if $users{$uid};
	my $user_info=get_json("https://$domain.campfirenow.com/users/$uid.json");
	$users{$uid}=$user_info->{'user'}->{'name'};
	return getuser($uid);
}

sub print_help
{
	print "Enter commands:
/list - lists all rooms
/join - lists rooms to join
/join <room number> - joins a room
/quit - exits program
/images <on|off> -turns images on or off
/token - shows user api token
/users - lists users in room
/rooms - list rooms
/help - print this page
";
}
sub get_json
{
	my $url = shift || die ("No url passed to get_json");
	my $raw_json=`curl -s -u $token:0 $url`;
	my $json_data;
	eval {
		$json_data=parse_json($raw_json);
	};
												        
	if($@) {
		warn("Couldn't parse json for url $url\nReturned data: $raw_json\n");
		return 0;
	}
	return $json_data;
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
