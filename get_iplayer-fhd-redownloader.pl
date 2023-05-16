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
my %alreadyDownloadedHighDef;   # Programmes already downloaded in 1080p quality                        (download_history file format)
my %alreadyDownloadedStanDef;   # Programmes already downloaded in 720p or lower quality                (download_history file format)
my %alreadyDownloadedBothDef;   # Programmes already downloaded in both 1080p AND 720p or lower quality (download_history file format)
my %cachedProgrammes;           # Programmes in the get_iplayer tv.cache file                                                                     (tv.cache file format)
my %availableProgrammes;        # Programmes already downloaded only in 720p or lower quality that are available for download                     (tv.cache file format)
my %availableInFhd;             # Programmes already downloaded only in 720p or lower quality that are available in 1080p quality for download    (tv.cache file format with added fields; 'version', 'qualities' and 'download_size'))
my %infoCacheProgrammes;        # Programmes which have already had a get_iplayer --info query run against them                                   (tv.cache file format with added fields; 'version', 'qualities' and 'download_size')
my %ignoreList;                 # Programmes which are not to be checked for 1080p quality versions ever again. (download_history file format)
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
my $claInfoCacheFilePath = "$claRedownloaderDir" . 'info.cache';

# Variables to hold comand line arguments, and their defaults if not deliberately set
# Testing overrides
# my $claExecutablePath = '/usr/local/bin/get_iplayer';
# my $claDataDir = './get_iplayer_test_files';
# my $claDownloadHistoryFilePath = $claDataDir . '/download_history_shortened';
# my $claTVCacheFilePath = $claDataDir . '/tv.cache';
# my $claRedownloaderDir = $claDataDir . '/fhd-redownloader/';
# my $claLogFilePath = $claRedownloaderDir . 'activity.log';
# my $claIgnoreListFilePath = $claRedownloaderDir . 'ignore.list';
# my $claIgnoreListFilePath = $claRedownloaderDir . 'info.cache';

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
# Re-using the file format for the info.cache data with two additions to the hash; fhd and download_size
# index|type|name|episode|seriesnum|episodenum|pid|channel|available|expires|duration|desc|web|thumbnail|timeadded|
# Additions for info.cache --->>>                                                                                 |version|qualities|fhd_download_size|
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
        'timeadded' => $splitCachedProgammeReference->[14]
    );
    # The following three fields only exist in fhd-redownloader's info.cache file, not get_iplayer's tv.cache file
    if(scalar(@{$splitCachedProgammeReference}) == 18) {
        # when parsing tv.cache
        my %newProgrammeHash = (
            'version'           => 'unknown',
            'qualities'         => 'unknown',
            'fhd_download_size' => 0
        );
    }
    else {
        # when parsing info.cache
        my %newProgrammeHash = (
            'version'             => $splitCachedProgammeReference->[15],
            'qualities'           => $splitCachedProgammeReference->[16],
            'fhd_download_size' => $splitCachedProgammeReference->[17]
        );
    }

    $cachedProgrammeHashReference->{$splitCachedProgammeReference->[6]} = \%newProgrammeHash;
}

# Subroutine to add a programme to the info.cache file
sub addProgrammeToInfoCacheFile {
    # Arguments: $filehandle, \%infoCacheProgrammes, $pid, 
    my ($fhInfoCache, $infoCacheProgrammesReference, $pid) = @_;
    
    my $newInfoCacheLine = "$infoCacheProgrammesReference->{$pid}->{'index'}|$infoCacheProgrammesReference->{$pid}->{'type'}|";
    $newInfoCacheLine .= "$infoCacheProgrammesReference->{$pid}->{'name'}|$infoCacheProgrammesReference->{$pid}->{'episode'}|";
    $newInfoCacheLine .= "$infoCacheProgrammesReference->{$pid}->{'seriesnum'}|$infoCacheProgrammesReference->{$pid}->{'episodenum'}|";
    $newInfoCacheLine .= "$pid|$infoCacheProgrammesReference->{$pid}->{'channel'}|$infoCacheProgrammesReference->{$pid}->{'available'}|";
    $newInfoCacheLine .= "$infoCacheProgrammesReference->{$pid}->{'expires'}|$infoCacheProgrammesReference->{$pid}->{'duration'}|";
    $newInfoCacheLine .= "$infoCacheProgrammesReference->{$pid}->{'desc'}|$infoCacheProgrammesReference->{$pid}->{'web'}|";
    $newInfoCacheLine .= "$infoCacheProgrammesReference->{$pid}->{'thumbnail'}|$infoCacheProgrammesReference->{$pid}->{'timeadded'}|";
    $newInfoCacheLine .= "$infoCacheProgrammesReference->{$pid}->{'version'}|$infoCacheProgrammesReference->{$pid}->{'qualities'}|";
    $newInfoCacheLine .= "$infoCacheProgrammesReference->{$pid}->{'fhd_download_size'}|";

    # Add the programme to the info.cache
    say $fhInfoCache "$newInfoCacheLine";
}

# Subroutine to overwrite the info.cache file
sub overwriteInfoCacheFile {
    # Arguments: $filePath, \%infoCacheProgrammes, $logOutput
    # $logOutput is a boolean value, 0 or 1 and controls whether the subroutine outputs to the terminal and log file
    my ($filePath, $infoCacheProgrammesReference, $logOutput) = @_;
    $logOutput //= 0;

    open(my $fh, '>:encoding(UTF-8)', $filePath);

    foreach my $pid (keys %$infoCacheProgrammesReference) {
        addProgrammeToInfoCacheFile($fh, $infoCacheProgrammesReference, $pid);
        
        if($logOutput) {
            # Terminal output
            say "Added programme PID $pid \"$infoCacheProgrammesReference->{$pid}{'name'}, $infoCacheProgrammesReference->{$pid}{'episode'}\" to the info.cache file.";
            # Log file output
            say $fhLogFile "Added programme PID $pid \"$infoCacheProgrammesReference->{$pid}{'name'}, $infoCacheProgrammesReference->{$pid}{'episode'}\" to the info.cache file $filePath";
        }
    }
    close $fh;
}

# Subroutine to append the info.cache file
sub appendInfoCacheFile {
    my ($filePath, $programmes_ref, $pid, $logOutput) = @_;
    $logOutput //= 0;

    open(my $fh, '>>:encoding(UTF-8)', $filePath);
    addProgrammeToInfoCacheFile($fh, $programmes_ref, $pid);
    close $fh;
    
    if($logOutput){
        # Terminal output
        say "Added programme PID $pid \"$programmes_ref->{$pid}{'name'}, $programmes_ref->{$pid}{'episode'}\" to the info.cache file.";
        # Log file output
        say $fhLogFile "Added programme PID $pid \"$programmes_ref->{$pid}{'name'}, $programmes_ref->{$pid}{'episode'}\" to the info.cache file $filePath";
    }
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

    # Check for 18 elements in the splitProgrammeInfo array
    # Need '-1' to ensure empty fields in the file format are still translated into elements in the array
    my @splitProgrammeInfo = split(/\|/, $programmeInfo, -1);
    my $numElements = scalar(@splitProgrammeInfo) - 1;
    if($numElements != 18) {
        say $fhLogFile "download_history line $downloadHistorylineCounter: Number of elements in the line is not 18 ($numElements): $programmeInfo";
        $downloadHistoryErrorCounter++;
        next;
    }

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
my $cacheRefreshCommand = "$claExecutablePath --refresh";
say $fhLogFile "Refreshing get_iplayer's tv.cache file using the command $cacheRefreshCommand";
say $fhLogFile '';
$cacheRefreshOutput = `$cacheRefreshCommand`;
$cacheRefreshExitCode = $? >> 8;
if($cacheRefreshExitCode == 0) {
    # Terminal output
    say "Successfully refreshed get_iplayer's tv.cache file.";
    # Log file output
    say $fhLogFile "Successfully refreshed get_iplayer's tv.cache file.";
}
else {
    # Terminal output
    say "Error: Failed to refresh get_iplayer's tv.cache file, exit code $cacheRefreshExitCode.";
    # Log file output
    say $fhLogFile "Error: Failed to refresh get_iplayer's tv.cache file, exit code $cacheRefreshExitCode.";
}

# Parse get_iplayer's tv.cache file
# tv.cache file format for reference
# index|type|name|episode|seriesnum|episodenum|pid|channel|available|expires|duration|desc|web|thumbnail|timeadded|
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

# Parse the info.cache file, if it exists.
# It uses the same file format as the tv.cache file WITH ADDITIONS. tv.cache file format for reference:
# index|type|name|episode|seriesnum|episodenum|pid|channel|available|expires|duration|desc|web|thumbnail|timeadded|
# Additions for info.cache --->>>                                                                                 |version|qualities|fhd_download_size|
if(-f $claInfoCacheFilePath) {
    my $fhInfoCache;
    open($fhInfoCache, '<:encoding(UTF-8)', $claInfoCacheFilePath);
    say $fhLogFile "Errors encountered while parsing the info.cache file $claInfoCacheFilePath :";
    my $numErrorsInInfoCacheFile = 0;
    my $infoCacheLineCounter = 0;
    while(my $infoProgramme = <$fhInfoCache>) {
        my $infoCacheLineCounter++;
        chomp $infoProgramme;
        if($infoProgramme =~ /^[0-9]+\|/) {   
            my @splitCachedProgamme = split(/\|/, $infoProgramme, -1);
            my $numElements = scalar(@splitCachedProgamme) - 1;
            if($numElements != 18) {
                $numErrorsInInfoCacheFile++;
                say $fhLogFile "Line $infoCacheLineCounter: Number of elements in the line is not 18 ($numElements): $infoProgramme";
                next;
            }
            else {
                # Reusing the download_history file format for the info.cache file
                addCachedProgrammeData(\%infoCacheProgrammes, \@splitCachedProgamme, $fhLogFile);
            }
        }
    }
    if($numErrorsInInfoCacheFile == 0) {
        say $fhLogFile "None";
    }
    close $fhInfoCache;

    # Terminal output
    say "Number of TV programmes in the info.cache file is " . scalar(%infoCacheProgrammes);
    # Log file output
    say $fhLogFile "Number of TV programmes in the info.cache file is " . scalar(%infoCacheProgrammes);
    say $fhLogFile '';

    # Parse %infoCacheProgrammes and remove expired programmes
    # Directly comparing all infoCacheProgrammes expiry times with the time now is one way to do it.
    # Another approach would be to see if the %infoCacheProgrammes PIDs are in the up-to-date cachedProgrammes hash: If not, they've obviously (probably?) expired, so delete them.
    foreach my $pid (keys %infoCacheProgrammes) {
        if($infoCacheProgrammes{$pid}{'expires'} < time()) {
            # Log file output
            say $fhLogFile "Programme PID $pid \"$infoCacheProgrammes{$pid}{'name'}, $infoCacheProgrammes{$pid}{'episode'}\" has expired, removing it from the info.cache file.";
            delete($infoCacheProgrammes{$pid});
        }
    }

    # Terminal output
    say "Number of TV programmes in the info.cache file after removing expired programmes is " . scalar(%infoCacheProgrammes);
    # Log file output
    say $fhLogFile "Number of TV programmes in the info.cache file after removing expired programmes is " . scalar(%infoCacheProgrammes);
    say $fhLogFile '';

    # Overwrite info.cache file with updated list of programmes now that expired programmes have been removed from the infoCacheProgrammes hash.
    overwriteInfoCacheFile($claInfoCacheFilePath, \%infoCacheProgrammes, 1);

}
else {
    # NB: It is not necessarily an error if no info.cache file exists. This is purely informational.
    # Terminal output
    say "No info.cache file found";
    # Log file output
    say $fhLogFile "No info.cache file found";
    say $fhLogFile '';
}
# There is now an updated info.cache file and an updated infoCacheProgrammes hash in the same state.

# # use `get_iplayer --info --pid=[PID] to check which available programmes are available in fhd quality`
# Terminal output
say "Checking which already downloaded programmes are available for download in 1080p quality now...";
say "Please be patient, this may take a (very) long time...";
# Log file output
say $fhLogFile "Checking which already downloaded programmes are available for download in 1080p quality now...";
my $numAvailableProgrammes = scalar(%availableProgrammes);
my $currentProgrammeNumber = 0;
foreach my $pid (keys %availableProgrammes) {
    $currentProgrammeNumber++;
    my $progressIndicator = $currentProgrammeNumber . '/' . $numAvailableProgrammes . ':';
    
    # Get programme info, repeating a maximum of $infoMaxAttempts in case of failure
    if(exists $infoCacheProgrammes{$pid}) {
        # Do NOT run a get_iplayer --info command, it is unnecessary as the programme information is already cached locally
        # Check for fhd in the value of the 'qualities' key in the infoCacheProgrammes hash entry for the programme
        
        # Terminal output
        say "$progressIndicator Cached programme information available for available programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"...";
        # Log file output
        say $fhLogFile "$progressIndicator Cached programme information available for available programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"...";

        if($infoCacheProgrammes{$pid}{'qualities'} =~ /fhd/) {
            # Add the programme to the availableInFhd hash
            $availableInFhd{$pid} = $infoCacheProgrammes{$pid};
            
            # Terminal output
            say "$progressIndicator 1080p quality version available for programme with PID $pid; \"$availableInFhd{$pid}{'name'}, $availableInFhd{$pid}{'episode'}\".";
            # Log file output
            say $fhLogFile "$progressIndicator 1080p quality version available for programme with PID $pid; \"$availableInFhd{$pid}{'name'}, $availableInFhd{$pid}{'episode'}\".";
        }
        else {
            # Terminal output
            say "$progressIndicator Only standard quality version available for programme with PID $pid; \"$availableInFhd{$pid}{'name'}, $availableInFhd{$pid}{'episode'}\".";
            # Log file output
            say $fhLogFile "$progressIndicator Only standard quality version available for programme with PID $pid; \"$availableInFhd{$pid}{'name'}, $availableInFhd{$pid}{'episode'}\".";
        }
    }
    else {
        # Run a get_iplayer --info command

        # Terminal output
        say "$progressIndicator No cached programme information available. Querying get_iplayer for information about available programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"...";
        # Log file output
        say $fhLogFile "$progressIndicator No cached programme information available. Querying get_iplayer for information about available programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"...";

        # get programme info
        my $infoCommand = "$claExecutablePath --info --pid=$pid";
        my $infoOutput = `$infoCommand`;
        my $infoExitCode = 1;
        my $infoAttempts = 0;
        my $infoMaxAttempts = 4;
        my $downloadSize = 0;

        while($infoExitCode != 0 && $infoAttempts < $infoMaxAttempts) {
            $infoOutput = `$infoCommand`;
            $infoExitCode = $? >> 8;
            $infoAttempts++;
            $totalGetIplayerErrors++;
        }
        # TODO: Remove this after testing. Debugging output only. 
        # say "get_iplayer --info exit code: $infoExitCode";
        # say "$infoOutput";

        if($infoExitCode == 0) {
            # Reference lines from --info output:
            # qualities:       audiodescribed: sd,web,mobile
            # qualities:       original: fhd,hd,sd,web,mobile
            # qualitysizes:    audiodescribed: sd=378MB,web=378MB,mobile=119MB [estimated sizes]
            # qualitysizes:    original: fhd=1819MB,hd=1157MB,sd=655MB,web=378MB,mobile=119MB [estimated sizes]

            # Add the programme to the infoCacheProgrammes hash regardless of whether an fhd quality version is available, but handle fhd and non-fhd differently
            # fhd version available first
            # A regex to match zero or more whitespace characters
            if($infoOutput =~ /^qualities:\s*((?:(?!signed|audiodescribed)\S)+): (.*fhd.*)$/) {
                $infoCacheProgrammes{$pid} = $availableProgrammes{$pid};
                # Now need to provide values for the aditional keys, version, qualities and qualitysizes that infoCacheProgrammes has
                # Include all available qualities, it needs to go in the infoCacheProgrammes array regardless of what's available to stop unnecessary future --info queries
                my $programmeVersion = $1;
                $infoCacheProgrammes{$pid}{'version'} = $programmeVersion;
                $infoCacheProgrammes{$pid}{'qualities'} = $2;
                # TODO: Remove this after testing. Debugging output only. 
                say "infoCacheProgrammes{$pid}{'version'} is $infoCacheProgrammes{$pid}{'version'}";
                say "infoCacheProgrammes{$pid}{'qualities'} is $infoCacheProgrammes{$pid}{'qualities'}";
                if($infoOutput =~ /^qualitysizes:\s*$programmeVersion:.*fhd=([0-9]+)MB/) {
                    $infoCacheProgrammes{$pid}{'fhd_download_size'} = $1;
                    # TODO: Remove this after testing. Debugging output only. 
                    say "infoCacheProgrammes{$pid}{'fhd_download_size'} is $infoCacheProgrammes{$pid}{'fhd_download_size'}";
                }
                else {
                    # This is an anomaly... if fhd was listed in 'qualities' there should be a corresponding fhd entry in 'qualitysizes'.
                    # Terminal output
                    say "$progressIndicator No fhd_download_size value available for fhd programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\".";
                    # Log file output
                    say $fhLogFile "$progressIndicator No fhd_download_size value available for fhd programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\".";
                    # Store a value of -1 in the case of no fhd version being available
                    $infoCacheProgrammes{$pid}{'fhd_download_size'} = -2;
                }
                # Add the programme to the availableInFhd hash
                $availableInFhd{$pid} = $infoCacheProgrammes{$pid};
            }
            # Only a non-fhd version available
            else {
                if($infoOutput =~ /^qualities:\s*((?:(?!signed|audiodescribed)\S)+): (.*)$/) {
                    $infoCacheProgrammes{$pid} = $availableProgrammes{$pid};
                    # Now need to provide values for the aditional keys, version, qualities and qualitysizes that infoCacheProgrammes has
                    # Include all available qualities, it needs to go in the infoCacheProgrammes array regardless of what's available to stop unnecessary future --info queries
                    my $programmeVersion = $1;
                    $infoCacheProgrammes{$pid}{'version'} = $programmeVersion;
                    $infoCacheProgrammes{$pid}{'qualities'} = $2;
                    $infoCacheProgrammes{$pid}{'fhd_download_size'} = -1;
                    # TODO: Remove this after testing. Debugging output only. 
                    say "infoCacheProgrammes{$pid}{'version'} is $infoCacheProgrammes{$pid}{'version'}";
                    say "infoCacheProgrammes{$pid}{'qualities'} is $infoCacheProgrammes{$pid}{'qualities'}";
                    say "infoCacheProgrammes{$pid}{'fhd_download_size'} is $infoCacheProgrammes{$pid}{'fhd_download_size'}";

                    # Terminal output
                    say "$progressIndicator Only a non-1080p quality version is available for programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\".";
                    # Log file output
                    say $fhLogFile "$progressIndicator Only a non-1080p quality version is available for programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\".";
                }
                else {
                    # Match either 'audiodescribed' or 'signed' in the 'qualities' line and save it in a capturing group
                    if($infoOutput =~ /^qualities:\s*((?:audiodescribed|signed)): (.*)$/) {
                        $infoCacheProgrammes{$pid} = $availableProgrammes{$pid};
                        # Now need to provide values for the aditional keys, version, qualities and qualitysizes that infoCacheProgrammes has
                        # Include all available qualities, it needs to go in the infoCacheProgrammes array regardless of what's available to stop unnecessary future --info queries
                        my $programmeVersion = $1;
                        $infoCacheProgrammes{$pid}{'version'} = $programmeVersion;
                        $infoCacheProgrammes{$pid}{'qualities'} = $2;
                        $infoCacheProgrammes{$pid}{'fhd_download_size'} = -1;
                        # TODO: Remove this after testing. Debugging output only. 
                        say "infoCacheProgrammes{$pid}{'version'} is $infoCacheProgrammes{$pid}{'version'}";
                        say "infoCacheProgrammes{$pid}{'qualities'} is $infoCacheProgrammes{$pid}{'qualities'}";
                        say "infoCacheProgrammes{$pid}{'fhd_download_size'} is $infoCacheProgrammes{$pid}{'fhd_download_size'}";

                        # Terminal output
                        say "$progressIndicator Only a non-1080p $infoCacheProgrammes{$pid}{'version'} version is available for programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\".";
                        # Log file output
                        say $fhLogFile "$progressIndicator Only a non-1080p $infoCacheProgrammes{$pid}{'version'} version is available for programme with PID $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\".";
                    }
                }
            }

            # Append the updated infoCacheProgrammes hash to the info.cache file
            appendInfoCacheFile($claInfoCacheFilePath, \%infoCacheProgrammes, $pid, 1);

            say $fhLogFile '';
        }
        else {
            # Report error, failed to get programme info in $infoMaxAttempts attempts
            # Terminal output
            say "$progressIndicator Failed $infoMaxAttempts times to get programme information for TV programme $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"";
            # Log file output
            say $fhLogFile "$progressIndicator Failed $infoMaxAttempts times to get programme information for TV programme $pid; \"$availableProgrammes{$pid}{'name'}, $availableProgrammes{$pid}{'episode'}\"";
        }
        say $fhLogFile '';

        # Exit if the total number of errors indicates a serious problem with get_iplayer
        if($totalGetIplayerErrors > $maximumPermissableGetIplayerErrors) {
            say $fhLogFile "$progressIndicator ERROR: Exiting due to more than $maximumPermissableGetIplayerErrors errors while attempting to run $claExecutablePath --info --pid=[PID] commands.";
            say $fhLogFile '';
            say "$progressIndicator ERROR: Exiting due to more than $maximumPermissableGetIplayerErrors errors while attempting to run $claExecutablePath --info --pid=[PID] commands.";
            say "       See log for further details: $claLogFilePath";
            last;
        }

        # WARNING: The BBC are blocking get_iplayer --info... commands after 50 consecutive queries.
        # TODO: Introduce a delay between each --info command OR Batch them into groups of <50, offer the user the choices and then do another <50?
        # TODO: OR just wait for the error, end the --info fetching loop and let the user choose from what has been fetched?
        # TODO: Try introducing a delay first... 
        # 15, 30 and 72 (50 queries/hour) second delays fail to circumvent the rate-limit.
        # 90 seconds to try next, but commented out for now as the info.cache code needs to be tested quicker.
        # sleep(90);
    }    
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
    my $expiryTime = $availableInFhd{$fhdPid}{'expires'};
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
    say "The download size of this programme is estimated to be " . prettyFileSize($availableInFhd{$fhdPid}{'fhd_download_size'}) . '.';
    say "The programme expires from iPlayer in $expiryDays days, $expiryRemainderHours hours and $expiryRemainderMinutes minutes at " . localtime($expiryTime);
    # Warning if the programme version is not 'original'
    if($availableInFhd{$fhdPid}{'version'} ne 'original') {
        say "WARNING: The programme version available now is not 'original', it is '$availableInFhd{$fhdPid}{'version'}'.";
        say "       : Do you still want to download it?";
        say "       : It may be worth comparing the runtime of this version to your existing download of this programme before overwriting it.";
        say "       : Especially if this version is 'editorial', where both runtime and content may vary considerably from what you already have.";
    }
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
            $cumulativeDownloadSize += $availableInFhd{$fhdPid}{'fhd_download_size'};
            $numProgrammesAddedToPvr++;
            # Terminal output
            say "Added programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to get_iplayer's PVR queue.";
            # Log file output
            say $fhLogFile "Added programme PID $fhdPid \"$availableInFhd{$fhdPid}{'name'}, $availableInFhd{$fhdPid}{'episode'}\" to get_iplayer's PVR queue.";
            say $fhLogFile "Command used: $pvrQueueCommand";

            # Remove the programme's information from the info.cache file
            delete($infoCacheProgrammes{$fhdPid});
            overwriteInfoCacheFile($claInfoCacheFilePath, \%infoCacheProgrammes);

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

        # Remove the programme's information from the info.cache file
        delete($infoCacheProgrammes{$fhdPid});
        overwriteInfoCacheFile($claInfoCacheFilePath, \%infoCacheProgrammes);
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

# Offer to run get_iplayer --pvr now
if ($numProgrammesAddedToPvr > 0) {
    my $pvrRunCommand = "$claExecutablePath --pvr";
    my $userInput;
    say "$numProgrammesAddedToPvr programmes have been added to get_iplayer's PVR.";
    say "Would you like to launch the PVR automatically as this script exits ([y]es/[n]o)?";
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
