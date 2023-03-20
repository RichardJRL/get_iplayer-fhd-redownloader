# get_iplayer-fhd-redownloader Description

## Summary
A program that parses a [`get_iplayer`](https://github.com/get-iplayer/get_iplayer) download_history file and offers to re-download previously downloaded programmes that are currently available in the newer FullHD 1080p quality option offered by the BBC. The option for FullHD downloads became available in `get_iplayer` circa February 2022.

It offers the user an interactive choice for what to do for each programme found available in the new FullHD 1080p quality:
1. Download it
2. Don't download it
3. Ignore it (remember not to ask the user about it again on subsequent runs)
4. Stop processing programmes and quit.

The programmes offered for download are sorted soonest-expiring first, so even if the user quits before reviewing the entire list, the most urgent programmes have always been presented to them. 

**NB:** `get_iplayer` must be installed on the system that this program is run on. This program relies on it being properly configured and will respect currently defined preferences such as download directories, metadata downloading etc. which are saved in the user's `~/.get_iplayer/options` file.
## Usage
### Command Line Arguments & Files Used
The program will run without any command line arguments being specified - and will only alert the user to provide the locations of essential files as command line arguments if it can't find them in their default locations.

It requires read-only access to two `get_iplayer` created files:
- `~/.get_iplayer/download_history`
- `~/.get_iplayer/tv.cache`
  
It writes to two new files in a new subdirectory of the user's hidden `~/.get_iplayer` directory:
- `~/.get_iplayer/fhd-redownloader/ignore.list`
- `~/.get_iplayer/fhd-redownloader/activity.log`

```
# The get_iplayer executable:
--get_iplayer-executable-path [/path/to/get_iplayer]

# get_iplayer files:
--download-history [/path/to/get_iplayer's/download_history]
--tv-cache [/path/to/get_iplayer's/tv.cache]

# fhd-redownloader files:
--log-file [/path/to/fhd-redownloader's_log_file]
--ignore-list [/path/to/fhd-redownloader's_ignore_list]
```
### Usage Examples
```
# Default operation:
perl get_iplayer-fhd-redownloader.pl

# Specify a custom location for get_iplayer and the fhd-redownloader log file:
perl get_iplayer-fhd-redownloader.pl --get_iplayer-executable-path /tmp/get_iplayer --log-file /tmp/activity.log
```
## Detailed Description

This is a Perl script to parse a `~/.get_iplayer/download_history` file and extract a list of all TV programmes that have not been downloaded in the newer `--tv-quality=fhd` 1080p resolution, which is indicated in the `download_history` file by:
- `dashfhd[1-3]`
- `hlsfhd[1-3]`

**NB:** In the `download_history` file, the following are earlier quality descriptors that refer only to 720p resolution downloads despite the `fhd` portion of their name:
- `hvfhd[1-3]`
- `dvfhd[1-3]`

**Aside:** `cat ~/.get_iplayer/download_history | awk -F '|' '{print $6}' | grep fhd | sort | uniq` will summarise the range of `fhd` quality descriptors, for both 720p and 1080p, that are already in the `download_history` file.

The Perl script will then take the list of TV programme PIDs that have not been downloaded in 1080p and search the `~/.get_iplayer/tv.cache` file to see if any of them are currently available on iPlayer.

After assembling a list of those TV programmes not already downloaded which are currently available on iPlayer, it will run the command `get_iplayer --info --pid=[PID]` to discover if they are now available in the new `fhd` 1080p resolution. This may take a *very, very* long time.

**Aside:** Batching PIDs in the `get_iplayer --info --pid=[PID1],[PID2],[PID3]` command does not appear to speed up the process. In my testing, it merely makes the process of retrieving programme information more error prone.

**Aside:** After running the command `get_iplayer --info --pid=[PID]`, the line containing the relevant information begins `qualities:`, e.g.
`qualities:       original: fhd,hd,sd,web,mobile`

If currently available programmes are available in `fhd`, it will queue them for download with the command `get_iplayer --pvr-queue --tv-quality=fhd --force --pid=[PID]`. Explicitly setting `--tv-quality=fhd` ensures that only the `fhd` version will be downloaded, and no bandwidth will be wasted on re-downloading any lower-quality version.

**Aside:** To instruct `get_iplayer` to try to obtain future programmes in FullHD 1080p quality whenever possible (not all programmes have a 1080p version), run the command: `get_iplayer --prefs-add --tv-quality="fhd,hd,sd,web"` and `get_iplayer` will first try to obtain the highest-quality version available, falling back to progressively lower quality versions in event of failure.

After asking the user for what to do with each available programme, the program will offer to run the `get_iplayer --pvr` command as it exits. However, it may be better to schedule this as a background cronjob, rather than running immediately. Or to ensure that a utility such as `screen` or `tmux` is used to guard against disruption to what may be a very large and lengthy download.
# References:
## File Formats
### tv.cache
Official file description copied from the first line of the `tv.cache` file.
```
#index|type|name|episode|seriesnum|episodenum|pid|channel|available|expires|duration|desc|web|thumbnail|timeadded|
```
**NB:** If the cache does not index the full last-30 days of programmes when first refreshed with `get_iplayer --refresh`, try forcing a cache rebuild with `get_iplayer --cache-rebuild`.
### download_history
Reconstructed from a programme's accompanying `.xml` metadata file.
```
pid|name|episode|type|download_end_time|mode|filename|version|duration|desc|channel|categories|thumbnail|guidance|web|episodenum|seriesnum|
```
**NB:** `download_end_time` is the number of seconds since the Unix epoch that the download finished. Use the linux command `date --date="@[seconds_since_epoch]"` to get a human-readable 
time & date.
e.g:
```
> date --date="@1678257312"
Wed  8 Mar 06:35:12 GMT 2023
```
**NB:** Some Gaelic language programmes use an additional `|` character to separate the dual-language English and Gaelic titles in the 2nd `name` field. This breaks the file-format and may be impossible to detect and correct for. On the other hand, it should be possible to anchor `tv` or `radio` to the 4th element of the file format. A dual-language title will shift this into the 5th element and this CAN be simply checked.
Known problematic PIDs:
- m001bnvz (English Gaelic language separator in `name`)
  
**NB:** Some programmes appear to include a newline character in their programme description. This also breaks the file format.
Known problematic PIDs:
- p026vhj2 (Hidden newline followed by 6 tabs in `desc`)
- p026vhmr (Hidden newline followed by 6 tabs in `desc`)
- p026vhrd (Hidden newline followed by 6 tabs in `desc`)
- p026vg7w (Hidden newline followed by 6 tabs in `desc`)
- m000trt5 (Gaelic English language separated by newline in `desc`)
- p0dnvdrc (Multiple hidden newlines in `desc`)

These are the only problematic TV programme PIDs discovered in an 11000 line `download_history` file that spans the period from September 2012 to March 2023.

**Workaround:**
- Ignore zero-length lines
- Only parse 17 element lines
- Write non-conforming lines to a log file and forget about them in the program flow thereafter. Users will have to sort these out manually.
## Links
- get_iplayer [GitHub](https://github.com/get-iplayer/get_iplayer)
- get_iplayer [Wiki](https://github.com/get-iplayer/get_iplayer/wiki)
- get_iplayer [recording quality information](https://github.com/get-iplayer/get_iplayer/wiki/modes)
- get_iplayer [fhd quality commit](https://github.com/get-iplayer/get_iplayer/commit/e89c643cf7667849e98ff25643664b20e5f16dfa)
- BBC Programme Identifiers [(PIDs)](https://en.wikipedia.org/wiki/BBC_Programme_Identifier)
## Support this Project
<a href='https://ko-fi.com/richardjrl' target='_blank'><img height='35' style='border:0px;height:46px;' src='https://az743702.vo.msecnd.net/cdn/kofi3.png?v=0' border='0' alt='Buy Me a Coffee at ko-fi.com' />
