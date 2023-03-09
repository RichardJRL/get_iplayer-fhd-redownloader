#!/usr/bin/env perl

use strict;
use warnings;
use autodie;
use Getopt::Long;
use feature 'say';
#use File::Spec;

# Variables to hold program data
my @alreadyDownloadedHighDef;
my @alreadyDownloadedStanDef;
my @alreadyDownloadedBothDef;

# Variables to hold comand line arguments, and their defaults if not deliberately set
# System defaults
# my $claExecutablePath = '/usr/bin/get_iplayer';
# my $claDataDir = '~/.get_iplayer';
# my $claDownloadHistoryFilePath = $claDataDir . "/download_history";
# my $claTVCacheFilePath = $claDataDir . "/tv.cache";
# Testing overrides
my $claExecutablePath = '/usr/bin/get_iplayer';
my $claDataDir = './get_iplayer_test_files';
my $claDownloadHistoryFilePath = $claDataDir . "/download_history";
my $claTVCacheFilePath = $claDataDir . "/tv.cache";

# Parse command line arguments
GetOptions('get_iplayer-executable-path=s' => \$claExecutablePath);
GetOptions('get_iplayer-data-dir=s' => \$claDataDir);
GetOptions('download-history=s' => \$claDownloadHistoryFilePath);
GetOptions('tv-cache=s' => \$claTVCacheFilePath);

# Display summary of key variables, showing whether they are the defaults or have been modified by command line arguments
say("get_iplayer executable path is: $claExecutablePath");
say("get_iplayer data directory is: $claDataDir");
say("Download history file path is: $claDownloadHistoryFilePath");
say("Download history file path is: $claTVCacheFilePath");

# Split the download_history file into two different arrays of
# sd quality downloads (@alreadyDownloadedStanDef) and fhd quality downloads (@alreadyDownloadedHighDef)
my $fhDownloadHistory;
open($fhDownloadHistory, '<:encoding(UTF-8)', $claDownloadHistoryFilePath);
while(my $line = <$fhDownloadHistory>) {
    chomp $line;
    # Match programmes already downloaded in fhd quality
    if ($line =~ /([a-zA-Z0-9]\|.*\|.*\|tv\|.*\|dashfhd[0-9]|hlsfhd[0-9])/) {
        push(@alreadyDownloadedHighDef,$line);
    }
    # Match programmes that do not exist in fhd quality
    else {
        push(@alreadyDownloadedStanDef,$line);
    }
}
close $fhDownloadHistory;

# Search the @alreadyDownloadedStanDef array for any programmes that have already been 
# re-downloaded in fhd quality and are present in the @alreadyDownloadedHighDef array
foreach my $fhdDownload (@alreadyDownloadedHighDef) {
    # Cut the PID out of the string (first 8 chars)
    my $pid = (split(/\|/, $fhdDownload))[0];
    # say($pid);
    foreach my $sdDownload (@alreadyDownloadedStanDef) {
        if($sdDownload =~ /$pid/) {
            # Record what the duplicate is
            push(@alreadyDownloadedBothDef,$fhdDownload);
        }
    }
}
# Summarise progress
say("Number of programmes in the standard quality downloads array is " . scalar(@alreadyDownloadedStanDef));
say("Number of programmes in the full HD  quality downloads array is " . scalar(@alreadyDownloadedHighDef));
say("Number of programmes in found in both download arrays is " . scalar(@alreadyDownloadedBothDef));
# say("The PIDs in the duplicates array are @alreadyDownloadedBothDef");

# Delete all programmes in the @alreadyDownloadedBothDef array from the from the @alreadyDownloadedStanDef array
foreach my $duplicateProgramme (@alreadyDownloadedBothDef) {
    my $duplicatePid = (split(/\|/, $duplicateProgramme))[0];
    @alreadyDownloadedStanDef = grep { $_ !~ /$duplicatePid/ } @alreadyDownloadedStanDef;
}
say("Number of programmes in the standard quality downloads array after duplicate removal is " . scalar(@alreadyDownloadedStanDef));

# Search the tv.cache file for programmes are in the @alreadyDownloadedStanDef array
# and save them to the @programmesAvailable array. 
my $fhTvCache
open($fhTvCache, '<:encoding(UTF-8)', $claTVCacheFilePath);
while(my $line = <$fhTvCache>) {
    chomp $line;
    # Do stuff...
}

# use `get_iplayer --info --pid=[PID] to check which available programmes are available in fhd quality`

close $fhTvCache;