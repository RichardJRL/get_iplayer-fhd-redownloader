# get_iplayer-fhd-redownloader Description

This is a Perl script to parse a `~/.get_iplayer/download_history` file and extract a list of all TV programmes that have not been downloaded in the newer `--tv-quality=fhd` 1080p resolution, which is indicated in the `download_history` file by 
- `dashfhd[1-3]`
- `hlsfhd[1-3]`

NB: In the `download_history` file, 
- `hvfhd[1-3]`
- `dvfhd[1-3]`
  
are earlier quality descriptors that refer to 720p resolution downloads.

Aside: `cat ~/.get_iplayer/download_history | awk -F '|' '{print $6}' | grep fhd | sort | uniq` will summarise the range of `fhd` quality descriptors, for both 720p and 1080p, that are already in the `download_history` file.

The Perl script will then take the list of TV programme PIDs that have not been downloaded in 1080p and search the `~/.get_iplayer/tv.cache` file to see if any are currently available on iPlayer.

After assembling a list of those TV programmes not already downloaded which are available on iPlayer, it will run the command `get_iplayer --info --pid=[PID]` to discover if they are now available in the new `fhd` 1080p resolution.

Aside: After running the command `get_iplayer --info --pid=[PID]`, the line containing the relevant information begins `qualities:`, e.g.
`qualities:       original: fhd,hd,sd,web,mobile`

If they are not available in `fhd`, it will optionally add their details to a new `~/.get_iplayer/tv.no_fhd` file, to avoid future redownloading attempts.
If they are available in `fhd`, it will either
- Download them immediately with the command `get_iplayer --get --tv-quality=fhd --force --pid=[PID]`, or
- Queue them for download with the command `get_iplayer --pvr-queue --tv-quality=fhd --force --pid=[PID]`
depending on user preference.

# References:
## File Formats
### tv.cache
Official file description copied from the first line of the `tv.cache` file.
```
#index|type|name|episode|seriesnum|episodenum|pid|channel|available|expires|duration|desc|web|thumbnail|timeadded
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

These are the only problematic PIDs in 11000 line `download_history` file that spans the period from September 2012 to March 2023.

**Workaround:**
*Thoughts:*
- Check for NOT 17 elements in the line... Adjust based on type `tv|radio` to account for dual-language `name`.
- Check for `/^[a-zA-Z0-9]{8}\|/` to match PID & field separator at the beginning of the line. This will catch the newline in description. Could combine with previous line saved as a previous array?
- Skip completely blank lines.
- Can further anchor elements in the regexp based on 10 digit `download_end_time` and a multi-digit `duration`.
*Actual:*
- Ignore zero-length lines
- Only parse 17 element lines
- Write non-conforming lines to a log file and forget about them in the program flow thereafter. Users will have to sort these out manually.
## Links
- get_iplayer [GitHub](https://github.com/get-iplayer/get_iplayer)
- get_iplayer [Wiki](https://github.com/get-iplayer/get_iplayer/wiki)