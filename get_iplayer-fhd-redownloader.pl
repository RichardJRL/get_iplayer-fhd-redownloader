#!/usr/bin/env perl

use strict;
use warnings;
use autodie;
use Getopt::Long;
use feature 'say';
#use File::Spec;

################################################################################
# Variables
################################################################################

# Variables to hold program data
my %alreadyDownloadedHighDef;
my %alreadyDownloadedStanDef;
my %alreadyDownloadedBothDef;

# Variables to hold comand line arguments, and their defaults if not deliberately set
# System defaults
# my $claExecutablePath = '/usr/bin/get_iplayer';
# my $claDataDir = '~/.get_iplayer';
# my $claDownloadHistoryFilePath = $claDataDir . "/download_history";
# my $claTVCacheFilePath = $claDataDir . "/tv.cache";
# Testing overrides
my $claExecutablePath = '/usr/bin/get_iplayer';
my $claDataDir = './get_iplayer_test_files';
my $claDownloadHistoryFilePath = $claDataDir . '/download_history';
my $claTVCacheFilePath = $claDataDir . '/tv.cache';
my $claLogFilePath = './get_iplayer-fhd-redownloader.log';

################################################################################
# Subroutines
################################################################################

# Subroutine to add downloaded programme data to one of the %alreadyDownloaded... hashes
sub addDownloadedProgrammeData {
    my ($alreadyDownloadedHashReference, $programmeInfo) = @_;
    my @splitProgrammeInfo = split(/\|/, $programmeInfo);
    my $numElements = scalar(@splitProgrammeInfo);
    say("Number of elements in splitProgrammeInfo is $numElements");
    
    # Check for empty strings in the splitProgrammeInfo array
    for (my $i = 0; $i < @splitProgrammeInfo; $i++) {
        if (length($splitProgrammeInfo[$i]) == 0) {
            $splitProgrammeInfo[$i] = 'N/A';
            say("Writing N/A to zero-length element number $i");
        }
    }
    
    # Take contents of @splitProgrammeInfo array and convert them into a hash
    my %newProgrammeHash = ();
    $newProgrammeHash{'name'}       = "$splitProgrammeInfo[1]";
    $newProgrammeHash{'episode'}    = "$splitProgrammeInfo[2]";
    $newProgrammeHash{'type'}       = "$splitProgrammeInfo[3]";
    $newProgrammeHash{'download_end_time'} = "$splitProgrammeInfo[4]";
    $newProgrammeHash{'mode'}       = "$splitProgrammeInfo[5]";
    $newProgrammeHash{'filename'}   = "$splitProgrammeInfo[6]";
    $newProgrammeHash{'version'}    = "$splitProgrammeInfo[7]";
    $newProgrammeHash{'duration'}   = "$splitProgrammeInfo[8]";
    $newProgrammeHash{'desc'}       = "$splitProgrammeInfo[9]";
    $newProgrammeHash{'channel'}    = "$splitProgrammeInfo[10]";
    $newProgrammeHash{'categories'} = "$splitProgrammeInfo[11]";
    $newProgrammeHash{'thumbnail'}  = "$splitProgrammeInfo[12]";
    $newProgrammeHash{'guidance'}   = "$splitProgrammeInfo[13]";
    $newProgrammeHash{'web'}        = "$splitProgrammeInfo[14]";
    $newProgrammeHash{'episodenum'} = "$splitProgrammeInfo[15]";
    $newProgrammeHash{'seriesnum'}  = "$splitProgrammeInfo[16]";
    
    # Quick check to see if the PID has already been downloaded (e.g I re-downloaded a deleted programme)
    if(exists $alreadyDownloadedHashReference->{$splitProgrammeInfo[0]}) {
        say("Duplicate programme in the array");
    }

    # $alreadyDownloadedHashReference->{$splitProgrammeInfo[0]} = \%newProgrammeHash;
}

################################################################################
# Main Program
################################################################################

# Parse command line arguments
GetOptions('get_iplayer-executable-path=s' => \$claExecutablePath);
GetOptions('get_iplayer-data-dir=s' => \$claDataDir);
GetOptions('download-history=s' => \$claDownloadHistoryFilePath);
GetOptions('tv-cache=s' => \$claTVCacheFilePath);
GetOptions('log-file=s' => \$claLogFilePath);

# Display summary of key variables, showing whether they are the defaults or have been modified by command line arguments
say("get_iplayer executable path is: $claExecutablePath");
say("get_iplayer data directory is: $claDataDir");
say("Download history file path is: $claDownloadHistoryFilePath");
say("TV cache file path is: $claTVCacheFilePath");
say("Log file path is: $claTVCacheFilePath");

# Parse the download_history file and split its contents into two different arrays of
# sd quality downloads (%alreadyDownloadedStanDef) and fhd quality downloads (%alreadyDownloadedHighDef)
# Lines not conforming to the download_history file format will be diverted to a log file
# download_history file format for reference:
# pid|name|episode|type|download_end_time|mode|filename|version|duration|desc|channel|categories|thumbnail|guidance|web|episodenum|seriesnum|
my $fhLogFile;
open($fhLogFile, '>>:encoding(UTF-8)', $claLogFilePath);
say($fhLogFile, "# Program log: " . localtime);
my $fhDownloadHistory;
open($fhDownloadHistory, '<:encoding(UTF-8)', $claDownloadHistoryFilePath);
while(my $downloadedProgramme = <$fhDownloadHistory>) {
    chomp $downloadedProgramme;
    # Match programmes already downloaded in fhd quality
    if ($downloadedProgramme =~ /([a-zA-Z0-9]\|.*\|.*\|tv\|.*\|dashfhd[0-9]|hlsfhd[0-9])/) {
        addDownloadedProgrammeData(\%alreadyDownloadedHighDef, $downloadedProgramme);
    }
    # Match programmes that do not exist in fhd quality
    else {
        addDownloadedProgrammeData(\%alreadyDownloadedStanDef, $downloadedProgramme);
    }
}
close $fhDownloadHistory;

# Search the %alreadyDownloadedStanDef array for any programmes that have already been 
# re-downloaded in fhd quality and are present in the %alreadyDownloadedHighDef array
foreach my $pid (keys %alreadyDownloadedHighDef) {
    if (defined $alreadyDownloadedStanDef{$pid}) {
        $alreadyDownloadedBothDef{$pid} = $alreadyDownloadedStanDef{$pid};
    }
}
# Summarise progress
say("Number of programmes in the standard quality downloads array is " . scalar(%alreadyDownloadedStanDef));
say("Number of programmes in the full HD  quality downloads array is " . scalar(%alreadyDownloadedHighDef));
say("Number of programmes in found in both download arrays is " . scalar(%alreadyDownloadedBothDef));
# say("The PIDs in the duplicates array are %alreadyDownloadedBothDef");

# Delete all programmes in the %alreadyDownloadedBothDef array from the from the %alreadyDownloadedStanDef array
foreach my $pid (keys %alreadyDownloadedBothDef) {
    delete $alreadyDownloadedStanDef{$pid};
}
say("Number of programmes in the standard quality downloads array after duplicate removal is " . scalar(%alreadyDownloadedStanDef));

# Search the tv.cache file for programmes are in the %alreadyDownloadedStanDef array
# and save them to the @programmesAvailable array. 
# my $fhTvCache
# open($fhTvCache, '<:encoding(UTF-8)', $claTVCacheFilePath);
# while(my $line = <$fhTvCache>) {
#     chomp $line;
#     # Do stuff...
# }

# # use `get_iplayer --info --pid=[PID] to check which available programmes are available in fhd quality`

# close $fhTvCache;
close $fhLogFile;