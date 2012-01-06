use strict;
use warnings;

use File::Copy;

sub read_status($) {
	my ($statusfile) = @_;
	my $tmpfile = "/tmp/nagiosstatus.$$.tmp";
	
	my $loopcount=0;
	my %status;
	do {
		if(-f $tmpfile) {
			unlink($tmpfile);
		}
		copy($statusfile, $tmpfile);
		
		open FILE, "<", $tmpfile or die "Cannot read $tmpfile";
	
# Santify check the file; File should end in a line containing a "}"
		my $lastline = "";
		seek(FILE,-200, 2);
		while(<FILE>) {
			chomp();
			next if(/^\s*$/);
			s/^\s*//;
			s/\s*$//;
			$lastline = $_;
		}
		if($lastline ne "}") {
			sleep(1);
			next;
		}
		$loopcount++;
		if($loopcount > 5) {
			return undef;
		}
		seek(FILE, 0, 0);
		my %rec;
		while(<FILE>) {
			chomp();
			next if(/^\s*$/);
			s/^\s*//;
			s/\s*$//;
			if(s/^(\w+)\s*{$/$1/) {
				%rec = ();
				$rec{'_type'} = $_;
			}
			elsif(/(\w+)=(.*)$/) {
				$rec{$1} = $2;
			}
			elsif(/^}$/) {
				my $key;
				if($rec{'_type'} eq 'hoststatus') {
					$key = 'host:' . $rec{'host_name'};
				}
				if($rec{'_type'} eq 'servicestatus') {
					$key = 'service:' . $rec{'host_name'} . ":" . $rec{'service_description'};
				}
				if(defined $key) {
					my %s;
					foreach(qw/current_state last_hard_state state_type plugin_output/) {
						if(defined($rec{$_}) and (length($rec{$_}) > 0)) {
							$s{$_} = $rec{$_};
						}
					}
					$status{$key} = \%s;
				}
			}
		}
	} while(scalar(keys(%status)) == 0);
	rm($tmpfile);
	return(\%status);
}

# Build a hashref with states
# Input: 
#  1	hashref		hashref with statuses from function read_state
#  2	scalar		1=use hard states, 2=use all states
sub build_state($ $) {
	my ($input, $type) = @_;

	my %s;
	foreach(keys %$input) {
		if($type == 1) {
			$s{$_} = $input->{$_}->{'last_hard_state'}
		}
		elsif($type == 2) {
			$s{$_} = $input->{$_}->{'current_state'}
		}
	}
	return(\%s);
}

sub compare_states($ $) {
	my ($state1, $state2) = @_;

	my @changes;

	foreach(keys %$state1) {
		if(!exists($state2->{$_})) {
			push(@changes, "removed $_");
		}
	}
	foreach(keys %$state2) {
		if(!exists($state1->{$_})) {
			push(@changes, "added $_");
		}
		elsif($state1->{$_} != $state2->{$_}) {
			push(@changes, "changed $_");
		}
	}
	return(@changes);
}

sub run() {
	#my $nagstates = read_status("/var/cache/nagios3/status.dat");
	my $nagstates = read_status("status.dat");
	my $s = build_state($nagstates, 1);
	$nagstates = read_status("status2.dat");
	my $s2 = build_state($nagstates, 1);
	my @delta = compare_states($s, $s2);
	print Dumper(@delta);
}

1;
