#!/usr/bin/env perl

use strict;
use warnings;
use autodie;
use Data::Dumper;
use File::Path;
use File::HomeDir;
use Getopt::Long;
use Time::Piece;
use Time::Seconds;
use feature 'say';
#use File::Spec;

################################################################################
# Variables
################################################################################

# Variables
my $fhLogFile;

# Variables to hold program data
my %alreadyDownloadedHighDef;
my %alreadyDownloadedStanDef;
my %alreadyDownloadedBothDef;
my %cachedProgrammes;
my %availableProgrammes;
my %availableInFhd;
my %ignoreList;
my $totalGetIplayerErrors = 0;
my $maximumPermissableGetIplayerErrors = 50;
my $cumulativeDownloadSize = 0;
my $numProgrammesAddedToPvr = 0;

# Variables to hold comand line arguments, and their defaults if not deliberately set
# System defaults
my $claExecutablePath = '/usr/local/bin/get_iplayer';
my $claDataDir = File::HomeDir->my_home() . '/.get_iplayer/';
my $claDownloadHistoryFilePath = "$claDataDir" . 'download_history';
my $claTVCacheFilePath = "$claDataDir" . 'tv.cache';
my $claRedownloaderDir = "$claDataDir" . 'fhd-redownloader/';
my $claLogFilePath = "$claRedownloaderDir" . 'activity.log';
my $claIgnoreListFilePath = "$claRedownloaderDir" . 'ignore.list';

# Variables to hold comand line arguments, and their defaults if not deliberately set
# Testing overrides
# my $claExecutablePath = '/usr/local/bin/get_iplayer';
# my $claDataDir = './get_iplayer_test_files';
# my $claDownloadHistoryFilePath = $claDataDir . '/download_history_shortened';
# my $claTVCacheFilePath = $claDataDir . '/tv.cache';
# my $claRedownloaderDir = $claDataDir . '/fhd-redownloader/';
# my $claLogFilePath = $claRedownloaderDir . 'activity.log';
# my $claIgnoreListFilePath = $claRedownloaderDir . 'ignore.list';

################################################################################
# Subroutines
################################################################################

# Subroutine to add downloaded programme data to one of the %alreadyDownloaded... hashes
# Re-using the file format for the ignore.list file too.
sub addDownloadedProgrammeData {
    my ($alreadyDownloadedHashReference, $splitProgrammeInfoReference, $fhLogFile) = @_;
    
    # Take contents of @splitProgrammeInfo array and convert them into a hash
    my %newProgrammeHash = (
        'name'       => $splitProgrammeInfoReference->[1],
        'episode'    => $splitProgrammeInfoReference->[2],
        'type'       => $splitProgrammeInfoReference->[3],
        'download_end_time' => $splitProgrammeInfoReference->[4],
        'mode'       => $splitProgrammeInfoReference->[5],
        'filename'   => $splitProgrammeInfoReference->[6],
        'version'    => $splitProgrammeInfoReference->[7],
        'duration'   => $splitProgrammeInfoReference->[8],
        'desc'       => $splitProgrammeInfoReference->[9],
        'channel'    => $splitProgrammeInfoReference->[10],
        'categories' => $splitProgrammeInfoReference->[11],
        'thumbnail'  => $splitProgrammeInfoReference->[12],
        'guidance'   => $splitProgrammeInfoReference->[13],
        'web'        => $splitProgrammeInfoReference->[14],
        'episodenum' => $splitProgrammeInfoReference->[15],
        'seriesnum'  => $splitProgrammeInfoReference->[16]
    );

    $alreadyDownloadedHashReference->{$splitProgrammeInfoReference->[0]} = \%newProgrammeHash;
}

# Subroutine to add downloaded programme data to the hash storing tv.cache data
sub addCachedProgrammeData {
    my ($cachedProgrammeHashReference, $splitCachedProgammeReference, $fhLogFile) = @_;

    # Take contents of @splitProgrammeInfo array and convert them into a hash
    my %newProgrammeHash = (
        'index'     => $splitCachedProgammeReference->[0],
        'type'      => $splitCachedProgammeReference->[1],
        'name'      => $splitCachedProgammeReference->[2],
        'episode'   => $splitCachedProgammeReference->[3],
        'seriesnum' => $splitCachedProgammeReference->[4],
        'episodenum' => $splitCachedProgammeReference->[5],
        # pid is 6
        'channel'   => $splitCachedProgammeReference->[7],
        'available' => $splitCachedProgammeReference->[8],
        'expires'   => $splitCachedProgammeReference->[9],
        'duration'  => $splitCachedProgammeReference->[10],
        'desc'      => $splitCachedProgammeReference->[11],
        'web'       => $splitCachedProgammeReference->[12],
        'thumbnail' => $splitCachedProgammeReference->[13],
        'timeadded' => $splitCachedProgammeReference->[14],
        'download_size' => '0'
    );

    $cachedProgrammeHashReference->{$splitCachedProgammeReference->[6]} = \%newProgrammeHash;
}

# Subroutine to display a file size in a human-readable format
sub prettyFileSize {
    my $inputFileSize = shift(@_);
    if ($inputFileSize < 2048 ) {
        # Format in MB
        return sprintf("%.0f", $inputFileSize) . " MB";
    }
    else {
        # Format in GB
        return sprintf("%.1f", $inputFileSize/1024) . " GB";
    }
}

################################################################################
# Main Program
################################################################################

# Parse command line arguments
GetOptions('get_iplayer-executable-path=s' => \$claExecutablePath,
            'download-history=s' => \$claDownloadHistoryFilePath,
            'tv-cache=s' => \$claTVCacheFilePath,
            'log-file=s' => \$claLogFilePath,
            'ignore-list=s' => \$claIgnoreListFilePath);

# Check the validity of the various required paths:
my $pathErrorCounter = 0;
my $tempLogFile = '';
my $fhTempLogFile;
open($fhTempLogFile, '>', \$tempLogFile);
say $fhTempLogFile "# Program log: " . localtime;
say $fhTempLogFile '';

# Display summary of key variables, showing whether they are the defaults or have been modified by command line arguments
say $fhTempLogFile "Command line arguments & default values used:";
say $fhTempLogFile "get_iplayer executable path: $claExecutablePath";
say $fhTempLogFile "get_iplayer data directory: $claDataDir";
say $fhTempLogFile "get_iplayer download history file path: $claDownloadHistoryFilePath";
say $fhTempLogFile "get_iplayer TV cache file path: $claTVCacheFilePath";
say $fhTempLogFile "fhd-redownloader directory: $claRedownloaderDir";
say $fhTempLogFile "fhd-redownloader log file path: $claLogFilePath";
say $fhTempLogFile "fhd-redownloader ignore list file path: $claIgnoreListFilePath";
say $fhTempLogFile '';

# Perform file and directory path checks
say $fhTempLogFile "Checking for the existance of essential files and directories...";
# Check get_iplayer executable exists and is executable
say $fhTempLogFile "Checking for the get_iplayer executable...";
if(-e $claExecutablePath) {
    say $fhTempLogFile "get_iplayer executable exists at $claExecutablePath";
    if(!-x $claExecutablePath) {
        say $fhTempLogFile "Error: The get_iplayer executable exits at the path $claExecutablePath but get_iplayer is not executable.";
        $pathErrorCounter++;
    }
    else {
        say $fhTempLogFile "get_iplayer executable exists at $claExecutablePath and is executable.";
    }
}
else {
    say $fhTempLogFile "Error: The get_iplayer executable does not exist at the path $claExecutablePath";
    $pathErrorCounter++;
}

# Check the .get_iplayer directory exists, but first run get_iplayer to generate it if necessary (i.e. first run)
say $fhTempLogFile "Checking for get_iplayer's data directory...";
`$claExecutablePath -v`;
if(!-d $claDataDir) {
    say $fhTempLogFile "Error: The get_iplayer data directory does not exist at the path $claDataDir";
    $pathErrorCounter++;
}
else {
    say $fhTempLogFile "get_iplayer data directory exists at $claDataDir";
}

# Check the .get_iplayer/download_history file exists. Nothing to do if it can't be parsed.
say $fhTempLogFile "Checking for the get_iplayer download history file...";
if(!-f $claDownloadHistoryFilePath) {
    say $fhTempLogFile "Error: The get_iplayer download history file $claDownloadHistoryFilePath does not exist.";
    $pathErrorCounter++;
}
else {
    say $fhTempLogFile "get_iplayer download_history file exists at $claDownloadHistoryFilePath"
}

# Don't check if the tv.cache file exists here; it introduces a premature delay. It can be refreshed or rebuilt later.

# Check the fhd-redownloader subdirectory exists; not an error, just create it if absent.
say $fhTempLogFile "Checking for fhd-redownloader's data directory...";
if(!-d $claRedownloaderDir) {
    # Create if not, function returns a list if directories created. Test for 1 directory created.
    if(scalar(File::Path::make_path($claRedownloaderDir)) == 1) {
        say $fhTempLogFile "Created fhd-redownloader data directory $claRedownloaderDir";
    }
    else {
        say $fhTempLogFile "Error: Unable to create fhd-redownloader data directory $claRedownloaderDir";
        $pathErrorCounter++;
    }
}
else {
    say $fhTempLogFile "fhd-redownloader data directory exists at $claRedownloaderDir";
}

# Don't check for the fhd-redownloader activity.log or ignore.list files.
# Their absence is not an error and they can be created later.

# If errors encountered when checking for essential files and directories, print log to stdout and exit.
if($pathErrorCounter != 0) {
    say $fhTempLogFile "Exiting prematurely due to $pathErrorCounter errors encountered while checking for essential file and directory paths.";
    say $tempLogFile;
    exit;
}

# Setup permanent log file
open($fhLogFile, '>>:encoding(UTF-8)', $claLogFilePath);
# Copy everything from the $tempLogFile variable to the actual log file
say $fhLogFile $tempLogFile;
close $fhTempLogFile;

# Parse the download_history file and split its contents into two different arrays of
# sd quality downloads (%alreadyDownloadedStanDef) and fhd quality downloads (%alreadyDownloadedHighDef)
# Lines not conforming to the download_history file format will be diverted to a log file
# download_history file format for reference:
# pid|name|episode|type|download_end_time|mode|filename|version|duration|desc|channel|categories|thumbnail|guidance|web|episodenum|seriesnum|
my $downloadHistorylineCounter = 0;
my $fhDownloadHistory;
my $downloadHistoryErrorCounter = 0;
open($fhDownloadHistory, '<:encoding(UTF-8)', $claDownloadHistoryFilePath);
say $fhLogFile "Parsing the get_iplayer download_history file $claDownloadHistoryFilePath";
say $fhLogFile "Errors encountered while parsing the get_iplayer download_history file $claDownloadHistoryFilePath :";
while(my $programmeInfo = <$fhDownloadHistory>) {
    $downloadHistorylineCounter++;

    # Check for zero-length line
    chomp $programmeInfo;
    if (length($programmeInfo) == 0) {
        say $fhLogFile "download_history line $downloadHistorylineCounter: Blank line.";
        $downloadHistoryErrorCounter++;
        next;
    }

    # Check for 17 elements in the splitProgrammeInfo array
    # Need '-1' to ensure empty fields in the file format are still translated into elements in the array
    my @splitProgrammeInfo = split(/\|/, $programmeInfo, -1);
    my $numElements = scalar(@splitProgrammeInfo) - 1;
    if($numElements != 17) {
        say $fhLogFile "download_history line $downloadHistorylineCounter: Number of elements in the line is not 17 ($numElements): $programmeInfo";
        $downloadHistoryErrorCounter++;
        next;
    }

    # Check for empty strings in the splitProgrammeInfo array and replace them with 'N/A'
    # Commented for now as not really necessary
    # for (my $i = 0; $i < @splitProgrammeInfo; $i++) {
    #     if (length($splitProgrammeInfo[$i]) == 0) {
    #         $splitProgrammeInfo[$i] = 'N/A';
    #         say("Writing N/A to zero-length element number $i");
    #     }
    # }

    # Limit matches to TV programmes, exclude radio programmes
    if($programmeInfo =~ /^[a-zA-Z0-9]{8}\|.*\|.*\|tv\|/) {
        # Match programmes already downloaded in fhd quality
        if($programmeInfo =~ /^[a-zA-Z0-9]{8}\|.*\|.*\|tv\|.*\|(dashfhd[0-9]|hlsfhd[0-9])/) {
            addDownloadedProgrammeData(\%alreadyDownloadedHighDef, \@splitProgrammeInfo, $fhLogFile);
        }
        # Match programmes that do not exist in fhd quality
        else { 
            addDownloadedProgrammeData(\%alreadyDownloadedStanDef, \@splitProgrammeInfo, $fhLogFile);
        }
    }
}
close $fhDownloadHistory;
say $fhLogFile '';

# Summarise download_history errors for terminal output
if ($downloadHistoryErrorCounter != 0) {
    say "Warning: $downloadHistoryErrorCounter errors encountered while parsing get_iplayer's download_history file at $claDownloadHistoryFilePath";
    say "Warning: Check the fhd-redownloader activity log for further details at $claLogFilePath";
}

# Search the %alreadyDownloadedStanDef array for any programmes that have already been 
# re-downloaded in fhd quality and are present in the %alreadyDownloadedHighDef array
foreach my $pid (keys %alreadyDownloadedHighDef) {
    if (defined $alreadyDownloadedStanDef{$pid}) {
        $alreadyDownloadedBothDef{$pid} = $alreadyDownloadedStanDef{$pid};
    }
}
# Summarise progress
# Terminal output
say "Number of TV programmes already downloaded in standard quality is " . scalar(%alreadyDownloadedStanDef);
say "Number of TV programmes already downloaded in FullHD quality is " . scalar(%alreadyDownloadedHighDef);
say "Number of TV programmes already downloaded in both standard quality and FullHD is " . scalar(%alreadyDownloadedBothDef);
# Log file output
say $fhLogFile "Summary of $claDownloadHistoryFilePath file parsing:";
say $fhLogFile "Number of programmes in the standard quality downloads array is " . scalar(%alreadyDownloadedStanDef);
say $fhLogFile "Number of programmes in the full HD  quality downloads array is " . scalar(%alreadyDownloadedHighDef);
say $fhLogFile "Number of programmes in found in both download arrays is " . scalar(%alreadyDownloadedBothDef);
# say("The PIDs in the duplicates array are %alreadyDownloadedBothDef");

# Delete all programmes in the %alreadyDownloadedBothDef array from the from the %alreadyDownloadedStanDef array
foreach my $pid (keys %alreadyDownloadedBothDef) {
    delete $alreadyDownloadedStanDef{$pid};
}
say $fhLogFile "Number of programmes in the standard quality downloads array after duplicate removal is " . scalar(%alreadyDownloadedStanDef);
say $fhLogFile '';

# Refresh get_iplayer's tv.cache file
# TODO: Inspect exit code of refresh command, log, informational output to STDOUT too
my $cacheRefreshCommand = "$claExecutablePath --refresh";
say $fhLogFile "Refreshing get_iplayer's tv.cache file using the command $cacheRefreshCommand";
say $fhLogFile '';
`$cacheRefreshCommand`;
# Parse get_iplayer's tv.cache file
# tv.cache file format for reference
#index|type|name|episode|seriesnum|episodenum|pid|channel|available|expires|duration|desc|web|thumbnail|timeadded|
my $fhTvCache;
open($fhTvCache, '<:encoding(UTF-8)', $claTVCacheFilePath);
say $fhLogFile "Errors encountered while parsing the get_iplayer tv.cache file $claTVCacheFilePath :";
my $tvCacheLineCounter = 0;
while(my $cachedProgramme = <$fhTvCache>) {
    $tvCacheLineCounter++;
    chomp $cachedProgramme;
    if($cachedProgramme =~ /^[0-9]+\|/)
    {   
        my @splitCachedProgamme = split(/\|/, $cachedProgramme, -1);
        my $numElements = scalar(@splitCachedProgamme) - 1;
        if($numElements != 15) {
            say $fhLogFile "Line $tvCacheLineCounter: Number of elements in the line is not 15 ($numElements): $cachedProgramme";
            next;
        }
        addCachedProgrammeData(\%cachedProgrammes, \@splitCachedProgamme, $fhLogFile);
    }
}
close $fhTvCache;
# Terminal output
say "Number of TV programmes in the cache is " . scalar(%cachedProgrammes);
# Log file output
say $fhLogFile "Number of TV programmes in the cache is " . scalar(%cachedProgrammes);
say $fhLogFile '';

# Iterate over the %cachedProgrammes array to find programmes that are also are in the %alreadyDownloadedStanDef hash
# and save them to the %availableProgrammes array, sorted by expiry (newest first).
say $fhLogFile "Checking which programmes already downloaded in 720p quality or lower are available for download now...";
foreach my $cachedPid (keys %cachedProgrammes) {
    if(exists $alreadyDownloadedStanDef{$cachedPid}) {
        $availableProgrammes{$cachedPid} = $cachedProgrammes{$cachedPid};
    }
}
# say $fhLogFile Dumper(%availableProgrammes);
# Terminal output
say "Number of already downloaded TV programmes which are available now is " . scalar(%availableProgrammes);
# Log file output
say $fhLogFile "Number of already downloaded TV programmes which are available now is " . scalar(%availableProgrammes);
say $fhLogFile '';

# Open the ignore.list file for reading, parse contents.
# NB: Reusing the download_history file format for the ignore.list
if(-f $claIgnoreListFilePath) {
    say $fhLogFile "Parsing ignore.list file.";
    my $fhReadIgnoreList;
    my $ignoreListlineCounter = 0;
    open($fhReadIgnoreList, '<:encoding(UTF-8)', $claIgnoreListFilePath);
    while(my $ignoreListLine = <$fhReadIgnoreList>) {
        $ignoreListlineCounter++;

        # Check for zero-length line
        chomp $ignoreListLine;
        if (length($ignoreListLine) == 0) {
            say $fhLogFile "ignore.list line $ignoreListlineCounter: Blank line.";
            next;
        }

        # Check for 17 elements in the splitIgnoreListLine array
        # Need '-1' to ensure empty fields in the file format are still translated into elements in the array
        my @splitIgnoreListLine = split(/\|/, $ignoreListLine, -1);
        my $numElements = scalar(@splitIgnoreListLine) - 1;
        if($numElements != 17) {
            say $fhLogFile "ignore.list line $ignoreListlineCounter: Number of elements in the line is not 17 ($numElements): $ignoreListLine";
            next;
        }
        
        # Reusing the download_history file format for the ignore.list file
        addDownloadedProgrammeData(\%ignoreList, \@splitIgnoreListLine, $fhLogFile);
    }
    close $fhReadIgnoreList;
    # Terminal output
    say "There are " . scalar(%ignoreList) . " programmes in the ignore list.";
    # Log file output
    say $fhLogFile "There are " . scalar(%ignoreList) . " programmes in the ignore list.";
    say $fhLogFile '';
}

# Remove programmes on the ignore list from the availableProgrammes hash
foreach my $pid (keys %availableProgrammes) {
    # Check PID against ignore.list programmes...
    if(exists $ignoreList{$pid}) {
        # This PID is present in the ignore.list file
        # Terminal output
        say "Programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\" is in the ignore list, removing it from the list of available programmes...";
        # Log file output
        say $fhLogFile "Programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\" is in the ignore list, removing it from the list of available programmes...";
        say $fhLogFile '';
        delete %availableProgrammes{$pid};
    }
}
# Terminal output
say "Number of already downloaded TV programmes which are available now after checking against the ignore list is " . scalar(%availableProgrammes);
# Log file output
say $fhLogFile "Number of already downloaded TV programmes which are available now after checking against the ignore list is " . scalar(%availableProgrammes);
say $fhLogFile '';

# # use `get_iplayer --info --pid=[PID] to check which available programmes are available in fhd quality`
say $fhLogFile "Checking which already downloaded programmes are available for download in 1080p quality now...";
say "Checking which already downloaded programmes are available for download in 1080p quality now...";
say "Please be patient, this may take a (very) long time...";
# TODO: Implement Storable module to save progress with each iteration and reload on future runs?
my $numAvailableProgrammes = scalar(%availableProgrammes);
my $currentProgrammeNumber = 0;
foreach my $pid (keys %availableProgrammes) {
    $currentProgrammeNumber++;
    my $progressIndicator = $currentProgrammeNumber . '/' . $numAvailableProgrammes . ':';

    # get programme info
    my $infoCommand = "$claExecutablePath --info --pid=$pid";
    my $infoOutput = `$infoCommand`;
    my $infoExitCode = 1;
    my $infoAttempts = 0;
    my $infoMaxAttempts = 4;
    my $availableInFhd = 0;
    my $downloadSize = 0;

    # Terminal output
    say "$progressIndicator Querying get_iplayer for information about available programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"...";
    # Log file output
    say $fhLogFile "$progressIndicator Querying get_iplayer for information about available programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"...";
    # Get programme info, repeating a maximum of $infoMaxAttempts in case of failure
    while($infoExitCode != 0 && $infoAttempts < $infoMaxAttempts) {
        $infoOutput = `$infoCommand`;
        $infoExitCode = $? >> 8;
        $infoAttempts++;
        $totalGetIplayerErrors++;
    }
    # say "get_iplayer --info exit code: $infoExitCode";
    # say "$infoOutput";

    if($infoExitCode == 0) {
        # search --info output for fhd entry on the `qualities:` line. There may be more than one `qualities:` line but one match is sufficient.
        if($infoOutput =~ /qualities:.*:.*fhd/) {
            $availableInFhd = 1;
            $availableInFhd{$pid} = $availableProgrammes{$pid};
            say $fhLogFile "$progressIndicator 1080p quality version available for programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\".";

            # search for `qualitysizes: ... fhd=`
            if($infoOutput =~ /qualitysizes:.*:.*fhd=([0-9]+)MB/) {
                $downloadSize = $1;
                $availableInFhd{$pid}{'download_size'} = $downloadSize;
            }
        }
        else {
            # say $fhLogFile ""; # Including notice of no higher quality version for all programmes might be too verbose?
        }
    }
    else {
        # Report error, failed to get programme info in $infoMaxAttempts attempts
        # Terminal output
        say "$progressIndicator Failed $infoMaxAttempts times to get programme information for TV programme $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"";
        # Log file output
        say $fhLogFile "$progressIndicator Failed $infoMaxAttempts times to get programme information for TV programme $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"";
    }
    say $fhLogFile '';
    if($totalGetIplayerErrors > $maximumPermissableGetIplayerErrors) {
        say $fhLogFile "$progressIndicator ERROR: Exiting due to more than $maximumPermissableGetIplayerErrors errors while attempting to run $claExecutablePath --info --pid=[PID] commands.";
        say $fhLogFile '';
        say "$progressIndicator ERROR: Exiting due to more than $maximumPermissableGetIplayerErrors errors while attempting to run $claExecutablePath --info --pid=[PID] commands.";
        say "       See log for further details: $claLogFilePath";
        last;
    }
    # WARNING: THe BBC are blocking get_iplayer --info... commands after 50 consecutive queries.
    # TODO: Introduce a delay between each --info command OR Batch them into groups of <50, offer the user the choices and then do another <50?
    # TODO: OR just wait for the error, end the --info fetching loop and let the user choose from what has been fetched?
    # TODO: Try introducing a delay first... 
    #15 and 30 second delays fail to circumvent the rate-limit. Now trying 72 seconds as I suspect it may 50 queries per hour as the limit?
    sleep(72);
}

# say $fhLogFile '';
say $fhLogFile "There are " . scalar(%availableInFhd) . " programmes available for re-download in 1080p quality.";
say $fhLogFile '';

# Sort the programmes in the availableInFhd hash so that the ones with the shortest expiry date can be presented to the user first.
my @sortedAvailableInFhdArray = sort {
    $availableInFhd{$a}{'expires'} <=> $availableInFhd{$b}{'expires'}
} keys %availableInFhd;

# Offer an interactive prompt to chose whether to download or not (yes, no, ignore, quit) and 
# add the ignored programmes to an ignore file, so they are not presented upon a subsequent program run.

# Create/open the ignore.list file for appending
my $fhAppendIgnoreList;
open($fhAppendIgnoreList, '>>encoding(UTF-8)', $claIgnoreListFilePath);

# Offer user a cloice of whether to download the programme or not
# Choices (yes, no, ignore, quit)
# download_history file format for reference:
# pid|name|episode|type|download_end_time|mode|filename|version|duration|desc|channel|categories|thumbnail|guidance|web|episodenum|seriesnum|
foreach my $fhdPid (@sortedAvailableInFhdArray) {
    # Clearly display the programme expiry time
    # Current time (epoch seconds)
    my $currentTime = time();
    # Expiry time (epoch seconds)
    my $expiryTime = $availableInFhd{$fhdPid}{expires};
    # Time difference in seconds
    my $differenceTime = $expiryTime - $currentTime;

    # Create a Time::Seconds object from the difference in seconds
    my $differenceTimeObj = Time::Seconds->new($differenceTime);

    # Format the time difference in whole days, remainder hours and remainder minutes.
    my $expiryDays = int($differenceTimeObj / 86400);
    my $expiryRemainderHours = int(($differenceTimeObj % 86400) / 3600);
    my $expiryRemainderMinutes = int(($differenceTimeObj % 3600) / 60);

    say '';
    say "Programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" is available in 1080p quality.";
    say "The total download size of programmes already added to get_iplayer's pvr-queue in this session is estimated to be " . prettyFileSize($cumulativeDownloadSize) . '.';
    say "The download size of this programme is estimated to be " . prettyFileSize($availableInFhd{$fhdPid}{'download_size'}) . '.';
    say "The programme expires from iPlayer in $expiryDays days, $expiryRemainderHours hours and $expiryRemainderMinutes minutes at " . localtime($expiryTime);
    say "Would you like to add it to the download queue?";
    say "[y]es    - add it to the download queue.";
    say "[n]o     - do not download it this time (DEFAULT).";
    say "[i]gnore - add it to the ignore list.";
    say "[q]uit   - quit the program now.";
    say "Choose one of the options above [y/n/i/q] (default: n):";
    my $defaultInput = 'n';
    my $userInput;
    say $fhLogFile "Asking the user what to do with programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\"...";
    while (1) {
        $userInput = readline(STDIN);
        chomp $userInput;
        if (length($userInput) == 0) {
            # Terminal output
            say "Blank user input, selecting default option \'$defaultInput\'";
            # Log file output
            say $fhLogFile "Blank user input, selecting default option \'$defaultInput\'";
            $userInput = $defaultInput;
        }
        if ($userInput =~ /^[yniq]$/i) {
            # No `say` here, it is dealt with in each of the individual valid input clauses below
            last;
        }
        else {
            # Terminal output
            say "Invalid input: Choose one of the options [y/n/i/q] (n):";
            # Log file output
            say $fhLogFile "Invalid user input, reprompting...";
        }
    }

    # Yes: Programme to be downloaded
    if ($userInput =~ /^y$/i) {
        my $pvrQueueCommand = "$claExecutablePath --pvr-queue --tv-quality=fhd --force --pid=$fhdPid";
        my $pvrQueueCommandOutput= `$pvrQueueCommand`;
        my $pvrQueueCommandExitCode = $? >> 8;
        if ($pvrQueueCommandExitCode == 0) {
            $cumulativeDownloadSize += $availableInFhd{$fhdPid}{'download_size'};
            $numProgrammesAddedToPvr++;
            # Terminal output
            say "Added programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to get_iplayer's PVR queue.";
            # Log file output
            say $fhLogFile "Added programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to get_iplayer's PVR queue.";
            say $fhLogFile "Command used: $pvrQueueCommand";
        }
        else {
            # Error adding to get_iplayer's pvr
            # Terminal output
            say "Failed to add programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to get_iplayer's PVR queue.";
            say "See the log file $claLogFilePath for more information.";
            # Log file output
            say $fhLogFile "Failed to add programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to get_iplayer's PVR queue.";
            say $fhLogFile "Command used: $pvrQueueCommand";
            say $fhLogFile "Command exit code: $pvrQueueCommandExitCode";
            say $fhLogFile "Command output:";
            say $fhLogFile "$pvrQueueCommandOutput"
        }
    }

    # No: Programme not to be downloaded in this session
    if ($userInput =~ /^n$/i) {
        # Terminal output
        say "Not downloading programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" this time.";
        # Log file output
        say $fhLogFile "Not downloading programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" this time.";
    }
    
    # Ignore: Programme to be ignored. Write its details to the ignore.list file using the download_history file format.
    if ($userInput =~ /^i$/i) {
        my $newIgnoreListLine = "$fhdPid|$alreadyDownloadedStanDef{$fhdPid}{'name'}|$alreadyDownloadedStanDef{$fhdPid}{'episode'}|";
        $newIgnoreListLine .= "$alreadyDownloadedStanDef{$fhdPid}{'type'}|$alreadyDownloadedStanDef{$fhdPid}{'download_end_time'}|";
        $newIgnoreListLine .= "$alreadyDownloadedStanDef{$fhdPid}{'mode'}|$alreadyDownloadedStanDef{$fhdPid}{'filename'}|";
        $newIgnoreListLine .= "$alreadyDownloadedStanDef{$fhdPid}{'version'}|$alreadyDownloadedStanDef{$fhdPid}{'duration'}|";
        $newIgnoreListLine .= "$alreadyDownloadedStanDef{$fhdPid}{'desc'}|$alreadyDownloadedStanDef{$fhdPid}{'channel'}|";
        $newIgnoreListLine .= "$alreadyDownloadedStanDef{$fhdPid}{'categories'}|$alreadyDownloadedStanDef{$fhdPid}{'thumbnail'}|";
        $newIgnoreListLine .= "$alreadyDownloadedStanDef{$fhdPid}{'guidance'}|$alreadyDownloadedStanDef{$fhdPid}{'web'}|";
        $newIgnoreListLine .= "$alreadyDownloadedStanDef{$fhdPid}{'episodenum'}|$alreadyDownloadedStanDef{$fhdPid}{'seriesnum'}|";

        # Add the programme to the ignore list
        say $fhAppendIgnoreList "$newIgnoreListLine";

        # Terminal output
        say "Added programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to the ignore list.";
        # Log file output
        say $fhLogFile "Added programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to the ignore list file $claIgnoreListFilePath";
    }

    # Quit: Cleanly exit the program without processing any more programmes.
    if ($userInput =~ /^q$/i) {
        # Terminal output
        say "Not processing any more programmes...";
        # Log file output
        say $fhLogFile "User requested to quit before processing all available programmes...";
        last;
    }
    say '';
    say $fhLogFile '';
    # Don't place anything else here at the bottom of the loop
}
close $fhAppendIgnoreList;
say $fhLogFile '';

# Offer to run get_iplayer --pvr now (TODO: check command is correct!)?
if ($numProgrammesAddedToPvr > 0) {
    my $pvrRunCommand = "$claExecutablePath --pvr";
    my $userInput;
    say "$numProgrammesAddedToPvr programmes have been added to get_iplayer's PVR. Would you like to launch the PVR automatically as this script exits ([y]es/[n]o)?";
    while(1) {
        $userInput = readline(STDIN);
        chomp $userInput;
        if($userInput =~ /^[yn]$/i) {
            last;
        }
        else {
            # Terminal output
            say "Invalid input: Choose either [y]es or [n]o:";
            # Log file output
            say $fhLogFile "Asking user whether to run $pvrRunCommand but received invalid user input \'$userInput\', reprompting...";
        }
    }
    if($userInput =~ /^y$/i) {
        say $fhLogFile "Running $pvrRunCommand and exiting...";
        say $fhLogFile '';
        close $fhLogFile;
        system("exec $pvrRunCommand");        
    }
    else {
        close $fhLogFile;
    }
}

# TODO: Sort the availableProgrammes and/or availableInFhd array by the expires field