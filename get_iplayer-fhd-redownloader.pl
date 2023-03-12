#!/usr/bin/env perl

use strict;
use warnings;
use autodie;
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
my $lineCounter = 0;

my $fhDownloadHistory;
open($fhDownloadHistory, '<:encoding(UTF-8)', $claDownloadHistoryFilePath);
say $fhLogFile "Errors encountered while parsing $claDownloadHistoryFilePath file:";
while(my $programmeInfo = <$fhDownloadHistory>) {
    $lineCounter++;

    # Check for zero-length line
    chomp $programmeInfo;
    if (length($programmeInfo) == 0) {
        say $fhLogFile "Line $lineCounter: Blank line";
        next;
    }

    # Check for 17 elements in the splitProgrammeInfo array
    # Need '-1' to ensure empty fields in the file format are still translated into elements in the array
    my @splitProgrammeInfo = split(/\|/, $programmeInfo, -1);
    my $numElements = scalar(@splitProgrammeInfo) - 1;
    if($numElements != 17) {
        say $fhLogFile "Line $lineCounter: Number of elements in the line is not 17 ($numElements): $programmeInfo";
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

# Search the tv.cache file for programmes are in the %alreadyDownloadedStanDef array
# and save them to the @programmesAvailable array. 
# my $fhTvCache
# open($fhTvCache, '<:encoding(UTF-8)', $claTVCacheFilePath);
# while(my $line = <$fhTvCache>) {
#     chomp $line;
#     # Do stuff...
# }

# # use `get_iplayer --info --pid=[PID] to check which available programmes are available in fhd quality`

# Either offer an interactive prompt to chose whether to download or not (yes, no, ignore) and 
# add the ignored programmes to an ignore file, so they are not presented upon a subsequent program run.
# First, parse the ignore file if it exists...

# Then offer the choices, add to pvr-queue

# Offer to run get_iplayer --pvr now

# close $fhTvCache;
close $fhLogFile;
