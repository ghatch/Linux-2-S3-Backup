#!/usr/bin/perl

use Fcntl qw(LOCK_EX LOCK_NB);
use File::NFSLock;
use Date::Format;

my $datadirs = "/home /root /var/tools /www";

# Try to get an exclusive lock on myself.
my $lock = File::NFSLock->new($0, LOCK_EX|LOCK_NB);
die "$0 is already running!\n" unless $lock;

my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);
$year += 1900;
$mon  += 1;
my $datestring = time2str( "%m-%d-%Y", time );
$logfile="/var/log/s3backup-$datestring.log";

open( LOGFILE , ">> $logfile" )
    or die "Can't open file '$logfile'. $!\n";
select((select(LOGFILE), $| = 1)[0]); # autoflush LOGFILE

sub logh() {
    my $msg = shift(@_);
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $mon  += 1; $wday += 1; $year += 1900;

    my @months = qw { Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec };
    my $dts;
    $dts = sprintf("%04d%3s%02d %02d:%02d:%02d",
                   $year,$months[$mon],$mday,$hour,$min,$sec);
    my $pid = $$;
    printf LOGFILE ("$dts:$pid: $msg\n" , @_);
}

sub backupDir {
	&logh("Creating tarball of directories");
	$dirfilename="data-$datestring.tar.gz";
	if (-e "/backups/$dirfilename") {
		&logh("Error: Backup file already exists: /backups/$dirfilename");
	}
	else {
		my $dirbak=`tar czPvf "/backups/Data/$dirfilename" $datadirs`;
		&logh("Directories tarball has been created");
	}
	
}

sub mysqlBackup {
    my $user ="root";
    my $password = "### MYSQL PASSWORD ###";
    my $outputdir = "/backups/MySQL";
    my $mysqldump = "/usr/bin/mysqldump";
    my $mysql = "/usr/bin/mysql";
    
	&logh("Creating MySQL backup dump");
	$msqlfilename="mysql-$datestring.tar.gz";
	if (-e "/backups/$msqlfilename") {
		&logh("Error: MySQL backup file already exists: /backups/$dirfilename");
	}
	else {
		system("rm -rf $outputdir/*.gz");
		&logh("Deleted old backups..");
		my @dblist = `$mysql -u$user -p$password -e 'SHOW DATABASES;' | grep -Ev '(Database|information_schema)'`;
		for $db (@dblist) {
		    chomp($db);
		    my $execute = `$mysqldump -u $user -p$password $db | gzip > $outputdir/$db.sql.gz`;
		}
		my $mysqlbak=`tar czvf "/backups/Data/$msqlfilename" $outputdir/*.gz`;
		system("rm -rf $outputdir/*.gz");
		&logh("MySQL Backup dump has been created.");

	}
}

sub createOne {
	&logh("Merging backups into one file");
	my $filename="ServerBackup-$datestring.tar.gz";
	if (-e "/backups/$filename") {
		&logh("Error: Backup file already exists: /backups/$filename");
	}
	else {
		my $arbak=`tar czvf /backups/Archive/$filename /backups/Data/*.gz`;
		system("rm -rf /backups/MySQL/* /backups/Data/*");
		&logh("Merge complete.");
	}
}

sub syncS3 {
	&logh("Syncing to S3.. ");
	my $sync=`s3cmd sync --delete-removed /backups/Archive/ s3://GHsvrbackup >> $logfile`;
	if ($? == 0) { &logh("Sync to s3 complete."); }
}

sub cleanArchive {
	&logh("Removing backups older than 7 days");
	system("find /backups/Archive -type f -mtime +7 -print | xargs rm");
	&logh("Delete complete.");
}

&cleanArchive;

my $filename="ServerBackup-$datestring.tar.gz";
if (-e "/backups/Archive/$filename") {
        &logh("Error: Backup file already exists: /backups/$filename");
        exit 1;
}

&backupDir;
&mysqlBackup;
&createOne;
&syncS3;
