#!/usr/bin/env perl

use strict;
use warnings;
use autodie;
use Data::Dumper;
use File::Path;
use Getopt::Long;
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
my $totalGetIplayerErrors = 0;
my $maximumPermissableGetIplayerErrors = 50;

# Variables to hold comand line arguments, and their defaults if not deliberately set
# System defaults
# my $claExecutablePath = '/usr/bin/get_iplayer';
# my $claDataDir = '~/.get_iplayer/';
# my $claDownloadHistoryFilePath = $claDataDir . 'download_history';
# my $claTVCacheFilePath = $claDataDir . 'tv.cache';
# my $claRedownloaderDir = $claDataDir . '/fhd-redownloader/';
# my $claLogFilePath = $claDataDir . $claRedownloaderDir . 'activity.log';
# my $claIgnoreListFilePath = $claDataDir . $claRedownloaderDir . 'ignore.list';
#
# Testing overrides
my $claExecutablePath = '/usr/bin/get_iplayer';
my $claDataDir = './get_iplayer_test_files';
my $claDownloadHistoryFilePath = $claDataDir . '/download_history';
my $claTVCacheFilePath = $claDataDir . '/tv.cache';
my $claRedownloaderDir = $claDataDir . '/fhd-redownloader/';
my $claLogFilePath = $claRedownloaderDir . 'activity.log';
my $claIgnoreListFilePath = $claRedownloaderDir . 'ignore.list';


################################################################################
# Subroutines
################################################################################

# Subroutine to add downloaded programme data to one of the %alreadyDownloaded... hashes
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
    # Quick check to see if the PID has already been downloaded (e.g I re-downloaded a deleted programme)
    # Commented out as it makes for a very noisy log file.
    # if(exists $alreadyDownloadedHashReference->{$splitProgrammeInfoReference->[0]}) {
    #     say $fhLogFile "Duplicate PID: Programme $splitProgrammeInfoReference->[0] already added to the array ", caller($alreadyDownloadedHashReference);
    # }

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
    # Quick check to see if the PID has already been downloaded (e.g I re-downloaded a deleted programme)
    # Commented out as it makes for a very noisy log file.
    # if(exists $alreadyDownloadedHashReference->{$splitCachedProgammeReference->[0]}) {
    #     say $fhLogFile "Duplicate PID: Programme $splitCachedProgammeReference->[0] already added to the array ", caller($alreadyDownloadedHashReference);
    # }

    $cachedProgrammeHashReference->{$splitCachedProgammeReference->[6]} = \%newProgrammeHash;
}

################################################################################
# Main Program
################################################################################

# Parse command line arguments
GetOptions('get_iplayer-executable-path=s' => \$claExecutablePath);
GetOptions('download-history=s' => \$claDownloadHistoryFilePath);
GetOptions('tv-cache=s' => \$claTVCacheFilePath);
GetOptions('log-file=s' => \$claLogFilePath);
GetOptions('ignore-list=s' => \$claIgnoreListFilePath);

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
say $fhTempLogFile "fhd-redownloader log file path: $claTVCacheFilePath";
say $fhTempLogFile "fhd-redownloader ignore list file path: $claIgnoreListFilePath";
say $fhTempLogFile '';

# Perform file and directory path checks
say $fhTempLogFile "Checking for the existance of essential files and directories...";
# Check get_iplayer executable exists and is executable
say $fhTempLogFile "Checking for the get_iplayer executable...";
if(-e $claExecutablePath) {
    say $fhTempLogFile "get_iplayer executable exists at $claExecutablePath";
    if(!-x $claExecutablePath) {
        say $fhTempLogFile "Error: The get_iplayer executable exits at the path $claExecutablePath but get_iplayer is not executable";
        $pathErrorCounter++;
    }
    else {
        say $fhTempLogFile "get_iplayer executable exists at $claExecutablePath and is executable"
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
    say $fhTempLogFile "Error: The get_iplayer download history file $claDownloadHistoryFilePath does not exist";
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
    say $fhTempLogFile "Exiting prematurely due to $pathErrorCounter errors encountered while checking for essential file and directory paths";
    say $tempLogFile;
    exit;
}

# Setup permanent log file
# TODO: Change from overwrite to append mode >>
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
open($fhDownloadHistory, '<:encoding(UTF-8)', $claDownloadHistoryFilePath);
say $fhLogFile "Errors encountered while parsing the get_iplayer download_history file $claDownloadHistoryFilePath :";
while(my $programmeInfo = <$fhDownloadHistory>) {
    $downloadHistorylineCounter++;

    # Check for zero-length line
    chomp $programmeInfo;
    if (length($programmeInfo) == 0) {
        say $fhLogFile "Line $downloadHistorylineCounter: Blank line";
        next;
    }

    # Check for 17 elements in the splitProgrammeInfo array
    # Need '-1' to ensure empty fields in the file format are still translated into elements in the array
    my @splitProgrammeInfo = split(/\|/, $programmeInfo, -1);
    my $numElements = scalar(@splitProgrammeInfo) - 1;
    if($numElements != 17) {
        say $fhLogFile "Line $downloadHistorylineCounter: Number of elements in the line is not 17 ($numElements): $programmeInfo";
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

    # Match programmes already downloaded in fhd quality
    if($programmeInfo =~ /^[a-zA-Z0-9]{8}\|.*\|.*\|tv\|.*\|(dashfhd[0-9]|hlsfhd[0-9])/) {
        addDownloadedProgrammeData(\%alreadyDownloadedHighDef, \@splitProgrammeInfo, $fhLogFile);
    }
    # Match programmes that do not exist in fhd quality
    else { 
        addDownloadedProgrammeData(\%alreadyDownloadedStanDef, \@splitProgrammeInfo, $fhLogFile);
    }
}
close $fhDownloadHistory;
say $fhLogFile '';

# Search the %alreadyDownloadedStanDef array for any programmes that have already been 
# re-downloaded in fhd quality and are present in the %alreadyDownloadedHighDef array
foreach my $pid (keys %alreadyDownloadedHighDef) {
    if (defined $alreadyDownloadedStanDef{$pid}) {
        $alreadyDownloadedBothDef{$pid} = $alreadyDownloadedStanDef{$pid};
    }
}
# Summarise progress
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
say $fhLogFile "Number of already downloaded programmes which are available now is " . scalar(%availableProgrammes);
say $fhLogFile '';

# # use `get_iplayer --info --pid=[PID] to check which available programmes are available in fhd quality`
say $fhLogFile "Checking which already downloaded programmes are available for download in 1080p quality now...";
foreach my $pid (keys %availableProgrammes) {
    # TODO: Check PID against ignore.list programmes...

    # get programme info
    my $infoCommand = "$claExecutablePath --info --pid=$pid";
    my $infoOutput = `$infoCommand`;
    my $infoExitCode = 1;
    my $infoAttempts = 0;
    my $infoMaxAttempts = 4;
    my $availableInFhd = 0;
    my $downloadSize = 0;

    say $fhLogFile "";
    say $fhLogFile "Querying get_iplayer for information about available programme with PID $pid; \"$availableProgrammes{$pid}{'name'}\", \"$availableProgrammes{$pid}{'episode'}\"...";
    # Get programme info, repeating a maximum of $infoMaxAttempts in case of failure
    while($infoExitCode != 0 && $infoAttempts < $infoMaxAttempts) {
        $infoOutput = `$infoCommand`;
        $infoExitCode = $? >> 8;
        $infoAttempts++;
        $totalGetIplayerErrors++;
        # TODO: Insert subroutine here that compares totalGetIplayerErrors with maximumPermissableGetIplayerErrors and exit if greater.
    }
    say "get_iplayer --info exit code: $infoExitCode";
    say "$infoOutput";

    if($infoExitCode == 0) {
        my $fhInfoOutput;
        open($fhInfoOutput, '<', \$infoOutput);
        while(my $infoLine = <$fhInfoOutput>) {
            if($infoLine =~ /^qualities:.*fhd/ && $availableInFhd != 1) {
                $availableInFhd = 1;
                $availableInFhd{$pid} = $availableProgrammes{$pid};
                say $fhLogFile "1080p quality version available for programme with PID $pid; \"$availableProgrammes{$pid}{'name'}\", \"$availableProgrammes{$pid}{'episode'}\"...";
            }
            else {
                # say $fhLogFile ""; # Including notice of no higher quality version for all programmes might be too verbose?
            }

            # search for `qualitysizes: ... fhd=`
            if($infoLine =~ /^qualitysizes:.*fhd=([0-9]+)MB/ && $availableInFhd == 1) {
                $downloadSize = $1;
                $availableInFhd{$pid}{'download_size'} = $downloadSize;
                last;
            }
        }
        close $fhInfoOutput;
    }
    else {
        # Report error, failed to get programme info in $infoMaxAttempts attempts
        say $fhLogFile "Failed $infoMaxAttempts times to get programme information for TV programme $pid; \"$availableProgrammes{$pid}{'name'}\", \"$availableProgrammes{$pid}{'episode'}\"";
    }
}

say $fhLogFile '';
say $fhLogFile "There are " . scalar(%availableInFhd) . " programmes available for re-download in 1080p quality.";
say $fhLogFile '';

# Either offer an interactive prompt to chose whether to download or not (yes, no, ignore) and 
# add the ignored programmes to an ignore file, so they are not presented upon a subsequent program run.
# First, parse the ignore file if it exists...

foreach my $fhdPid (keys %availableInFhd) {
    say "foo";
}

# Then offer the choices, add to pvr-queue

# Offer to run get_iplayer --pvr now

# close $fhTvCache;
close $fhLogFile;
