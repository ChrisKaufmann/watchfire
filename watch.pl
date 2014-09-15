#!/usr/bin/perl
use warnings;
use strict;
use JSON::Parse 'parse_json';
use Term::ANSIColor qw(:constants);
my $token=shift || usage();
my $domain=shift || usage();
my $room=shift || usage();
my $convertimages=shift || 1;
$| = 1;


my %users;
my %entries;
my $room_url="https://$domain.campfirenow.com/room/$room";

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
		if($convertimages && $body=~m/http.*(\.jpg|\.jpeg|\.bmp|\.gif|\.png)$/)
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
	print ("Usage: $0 <token> <domain> <room id>\n\tex$0 1234123412341234 mydomain 1234 <0 disable images>");
	exit();
}
