/*****************************************************************************
 * release_name.c: test for vlc_release_name_parse() / _display()
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <vlc_common.h>
#include <vlc_strings.h>

struct display_case
{
    const char *name;
    const char *expected;
};

static const struct display_case display_cases[] =
{
    /* the formats from the feature request */
    { "Donnie.Darko.2001.REMASTERED.DC.1080p.BluRay.H264.AAC",
      "Donnie Darko (2001)" },
    { "Chappie.2015.2160p.4K.BluRay.x265.10bit.AAC5.1-[YTS.MX]",
      "Chappie (2015)" },

    /* real files, dotted */
    { "Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX[TGx].mkv",
      "Dune Part Two (2024)" },
    { "Fall.2.Deadpoint.2026.1080p.WEBRip.DD5.1.10bits.x265-Rapta.mkv",
      "Fall 2 Deadpoint (2026)" },
    { "Toy.Story.5.2026.2160p.4K.WEB.x265.10bit.AAC5.1-[YTS.GG - YTS.BZ].mkv",
      "Toy Story 5 (2026)" },
    { "Chappie.2015.2160p.4K.BluRay.x265.10bit.AAC5.1-[YTS.MX].mkv",
      "Chappie (2015)" },

    /* real files, spaces and brackets */
    { "Novocaine (2025) [1080p] [WEBRip] [x265] [10bit] [5.1] [YTS.MX]",
      "Novocaine (2025)" },
    { "The Exorcism of Emily Rose UNRATED (2005) [1080p]",
      "The Exorcism of Emily Rose (2005)" },
    { "Thunderbolts 2025 2160p AMZN WEB-DL DDP5.1 HDR HEVC-TBMovies.mkv",
      "Thunderbolts (2025)" },

    /* titles that the media library already half-cleaned */
    { "Donnie Darko 2001 REMASTERED DC", "Donnie Darko (2001)" },
    { "Chappie 2015 4K AAC5 1", "Chappie (2015)" },
    { "Dune 2021 4K HDR AAC5 1", "Dune (2021)" },
    { "Dune Part Two 2024 Atmos DV HDR FLUX", "Dune Part Two (2024)" },

    /* titles that look like years or contain numbers */
    { "1917.2019.1080p.BluRay.x264-SPARKS", "1917 (2019)" },
    { "2012.2009.720p.BluRay.x264", "2012 (2009)" },
    { "Blade.Runner.2049.2017.1080p.BluRay.x264", "Blade Runner 2049 (2017)" },
    { "Blade.Runner.2049.1080p.BluRay.x264", "Blade Runner 2049" },

    /* tags in front, hyphens and colons inside the title */
    { "[YTS.MX] Spider-Man.No.Way.Home.2021.1080p.WEBRip",
      "Spider-Man No Way Home (2021)" },
    { "Spider-Man: Into the Spider-Verse 2018 1080p", "Spider-Man: Into the Spider-Verse (2018)" },
    { "Ford.v.Ferrari.2019.1080p.BluRay", "Ford v Ferrari (2019)" },
    { "the.matrix.1999.1080p.bluray", "The Matrix (1999)" },

    /* no year: the edition word at the end of the title is trimmed */
    { "Movie.Name.UNRATED.1080p.BluRay.x264", "Movie Name" },

    /* TV */
    { "Breaking.Bad.S02E05.720p.HDTV.x264-CTU.mkv", "Breaking Bad - S02E05" },
    { "The.Mandalorian.2019.S01E03.1080p.WEB.H264", "The Mandalorian - S01E03" },
    { "Some.Show.1x07.HDTV", "Some Show - S01E07" },
    { "Nightfall - S1E1 Pilot", "Nightfall - S01E01" },
    { "Show.Name.S03.1080p.BluRay", "Show Name - Season 3" },

    /* human titles must not be touched */
    { "Stuck Overnight with My Buddy's Stepmom After He Left for the Village.mp4",
      "Stuck Overnight with My Buddy's Stepmom After He Left for the Village" },
    { "Slow Burn", "Slow Burn" },
    { "Paper Moon (2026)", "Paper Moon (2026)" },
    { "Everything Everywhere All at Once (2022)", "Everything Everywhere All at Once (2022)" },
    { "holiday video.mp4", "holiday video" },
    { "", "" },
};

int main(void)
{
    int failures = 0;

    for (size_t i = 0; i < ARRAY_SIZE(display_cases); i++)
    {
        char *got = vlc_release_name_display(display_cases[i].name);
        if (got == NULL || strcmp(got, display_cases[i].expected) != 0)
        {
            fprintf(stderr, "FAIL: \"%s\"\n   expected \"%s\"\n   got      \"%s\"\n",
                    display_cases[i].name, display_cases[i].expected,
                    got ? got : "(null)");
            failures++;
        }
        free(got);
    }

    /* fields */
    struct vlc_release_info info;

    int ret = vlc_release_name_parse("Donnie.Darko.2001.REMASTERED.DC.1080p.BluRay.H264.AAC", &info);
    assert(ret == 0);
    assert(!strcmp(info.title, "Donnie Darko"));
    assert(info.year == 2001);
    assert(info.season == 0 && info.episode == 0);
    assert(!strcmp(info.resolution, "1080p"));
    vlc_release_info_clean(&info);

    ret = vlc_release_name_parse("Chappie.2015.2160p.4K.BluRay.x265.10bit.AAC5.1-[YTS.MX]", &info);
    assert(ret == 0);
    assert(!strcmp(info.title, "Chappie"));
    assert(info.year == 2015);
    assert(!strcmp(info.resolution, "2160p"));
    vlc_release_info_clean(&info);

    ret = vlc_release_name_parse("Breaking.Bad.S02E05.720p.HDTV.x264-CTU", &info);
    assert(ret == 0);
    assert(!strcmp(info.title, "Breaking Bad"));
    assert(info.year == 0 && info.season == 2 && info.episode == 5);
    vlc_release_info_clean(&info);

    ret = vlc_release_name_parse("Slow Burn", &info);
    assert(ret == -1);
    assert(!strcmp(info.title, "Slow Burn"));
    assert(info.year == 0);
    vlc_release_info_clean(&info);

    /* a NULL name must not crash */
    ret = vlc_release_name_parse(NULL, &info);
    assert(ret == -1 && info.title == NULL);
    assert(vlc_release_name_display(NULL) == NULL);

    if (failures > 0)
    {
        fprintf(stderr, "%d release name case(s) failed\n", failures);
        return 1;
    }
    return 0;
}
