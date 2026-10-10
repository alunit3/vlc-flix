/*****************************************************************************
 * release_name.c: guess "Title (Year)" from release / torrent file names
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <vlc_common.h>
#include <vlc_strings.h>

/*
 * Approach
 * --------
 * "Donnie.Darko.2001.REMASTERED.DC.1080p.BluRay.H264.AAC" is split in tokens.
 * The title is everything before the release year, or before the first
 * "strong" marker (resolution, source, codec, audio format, SxxExx, a
 * [bracketed] tag, ...), whichever comes first. Trailing edition words
 * (UNRATED, REMASTERED, ...) are trimmed from the title. A name without any
 * marker is not a release name and is left alone.
 */

#define MAX_NAME   512
#define MAX_TOKENS 96

struct token
{
    const char *s;
    size_t len;
    bool bracket;   /* inside [ ] or { } */
    bool paren;     /* inside ( ) */
};

/* ASCII lower-cased copy of the part of the token before the first '-'
 * ("x265-Rapta" -> "x265"), and of the full token. */
struct lowtok
{
    char base[24];
    char full[24];
};

static void tok_lower(const struct token *t, struct lowtok *l)
{
    size_t n = t->len < sizeof(l->full) - 1 ? t->len : sizeof(l->full) - 1;
    size_t b = 0;

    for (size_t i = 0; i < n; i++)
        l->full[i] = (char)tolower((unsigned char)t->s[i]);
    l->full[n] = '\0';

    while (b < n && l->full[b] != '-')
        b++;
    memcpy(l->base, l->full, b);
    l->base[b] = '\0';
    if (t->len >= sizeof(l->full))     /* too long to be a marker word */
        l->base[0] = l->full[0] = '\0';
}

static bool in_list(const char *w, const char *const *list)
{
    for (; *list != NULL; list++)
        if (!strcmp(w, *list))
            return true;
    return false;
}

static bool all_digits(const char *s, size_t n)
{
    if (n == 0)
        return false;
    for (size_t i = 0; i < n; i++)
        if (!isdigit((unsigned char)s[i]))
            return false;
    return true;
}

static int max_year(void)
{
    time_t now = time(NULL);
    struct tm tm;

    if (gmtime_r(&now, &tm) == NULL)
        return 2100;
    return tm.tm_year + 1900 + 1;
}

static bool tok_is_year(const struct token *t, int maxyear)
{
    if (t->len != 4 || !all_digits(t->s, 4))
        return false;
    int y = atoi(t->s);
    return y >= 1900 && y <= maxyear;
}

static bool is_resolution(const struct lowtok *l)
{
    size_t n = strlen(l->base);

    if (!strcmp(l->base, "4k") || !strcmp(l->base, "8k") || !strcmp(l->base, "uhd"))
        return true;
    return n >= 4 && n <= 5 && (l->base[n - 1] == 'p' || l->base[n - 1] == 'i')
        && all_digits(l->base, n - 1);
}

/* S01E02, S01E02E03, 1x02 -> 1 and fills season/episode; S01 -> 2 (season only) */
static int parse_season_episode(const struct lowtok *l, int *season, int *episode)
{
    const char *p = l->base;
    int s, e;

    if (*p == 's' && isdigit((unsigned char)p[1]))
    {
        char *end;
        s = (int)strtol(p + 1, &end, 10);
        if (end - (p + 1) > 2)
            return 0;
        if (*end == '\0')
        {
            *season = s;
            *episode = 0;
            return 2;
        }
        if (*end == 'e' && isdigit((unsigned char)end[1]))
        {
            const char *q = end + 1;
            e = (int)strtol(q, &end, 10);
            if (end - q > 3)
                return 0;
            /* S01E02E03 / S01E02-E03: keep the first episode */
            if (*end == '\0' || *end == 'e' || *end == '-')
            {
                *season = s;
                *episode = e;
                return 1;
            }
        }
        return 0;
    }

    if (isdigit((unsigned char)*p))
    {
        char *end;
        s = (int)strtol(p, &end, 10);
        if (*end == 'x' && end - p <= 2 && isdigit((unsigned char)end[1]))
        {
            const char *q = end + 1;
            e = (int)strtol(q, &end, 10);
            if (*end == '\0' && end - q >= 2 && end - q <= 3)
            {
                *season = s;
                *episode = e;
                return 1;
            }
        }
    }
    return 0;
}

static bool is_source(const struct lowtok *l)
{
    static const char *const full[] = { "web-dl", "blu-ray", NULL };
    static const char *const base[] = {
        "bluray", "bdrip", "brrip", "bdremux", "remux", "webrip", "webdl",
        "hdrip", "hdtv", "pdtv", "dvdrip", "dvdscr", "hdcam", "telesync",
        "hdts", NULL
    };
    return in_list(l->full, full) || in_list(l->base, base);
}

static bool is_codec(const struct lowtok *l)
{
    static const char *const base[] = {
        "x264", "x265", "h264", "h265", "hevc", "avc", "xvid", "divx", "av1",
        "vp9", "10bit", "10bits", "8bit", "hi10p", "hdr", "hdr10", "hdr10+",
        "dovi", NULL
    };
    return in_list(l->base, base);
}

static bool is_audio(const struct lowtok *l)
{
    static const char *const prefix[] = {
        "aac", "ac3", "eac3", "ddp", "dd+", "dd5", "dd2", "dts", "truehd",
        "atmos", "flac", NULL
    };

    for (const char *const *p = prefix; *p != NULL; p++)
    {
        size_t n = strlen(*p);
        if (!strncmp(l->base, *p, n))
        {
            const char *rest = l->base + n;
            /* "aac", "aac5", "ddp5", "dts" but not "dtsomething" */
            if (all_digits(rest, strlen(rest)) || *rest == '\0' || !strcmp(rest, "+"))
                return true;
        }
    }
    return false;
}

/* Words that can follow the title or the year, but belong to the release.
 * Only used to trim the end of a title, never to find where it ends. */
static bool is_edition(const struct lowtok *l)
{
    static const char *const base[] = {
        "remastered", "unrated", "extended", "uncut", "theatrical", "imax",
        "proper", "repack", "internal", "limited", "multi", "dual", "hybrid",
        "dc", "directors", "director's", "cut", "edition", "special",
        "criterion", "final", "complete", NULL
    };
    return in_list(l->base, base);
}

static bool is_strong(const struct token *toks, size_t n, size_t i, int maxyear)
{
    const struct token *t = &toks[i];
    struct lowtok l;
    int s, e;

    if (i == 0)
        return false;           /* the first word is always part of the title */

    if (tok_is_year(t, maxyear))
        return false;           /* years are handled separately */

    if (t->bracket || t->paren)
        return true;            /* [1080p] [YTS.MX] (Extended Cut) */

    tok_lower(t, &l);
    if (l.base[0] == '\0')
        return false;

    if (is_resolution(&l) || is_source(&l) || is_codec(&l) || is_audio(&l))
        return true;
    if (parse_season_episode(&l, &s, &e) != 0)
        return true;

    /* two word markers: "Blu Ray", "WEB DL", "WEB Rip", "H 264" */
    if (i + 1 < n)
    {
        struct lowtok nx;
        tok_lower(&toks[i + 1], &nx);
        if ((!strcmp(l.base, "blu") && !strcmp(nx.base, "ray")) ||
            (!strcmp(l.base, "web") && (!strcmp(nx.base, "dl") || !strcmp(nx.base, "rip"))) ||
            (!strcmp(l.base, "h") && (!strcmp(nx.base, "264") || !strcmp(nx.base, "265"))))
            return true;
        /* a lone "WEB" followed by another marker: "4K.WEB.x265" */
        if (!strcmp(l.base, "web") && (is_codec(&nx) || is_audio(&nx) || is_resolution(&nx)))
            return true;
    }
    return false;
}

static size_t tokenize(char *buf, struct token *toks, size_t max)
{
    size_t n = 0;
    int br = 0, pa = 0;
    char *p = buf;

    while (*p != '\0' && n < max)
    {
        char c = *p;

        if (c == '[' || c == '{') { br++; p++; continue; }
        if (c == ']' || c == '}') { if (br > 0) br--; p++; continue; }
        if (c == '(')             { pa++; p++; continue; }
        if (c == ')')             { if (pa > 0) pa--; p++; continue; }
        if (c == ' ' || c == '.' || c == '_') { p++; continue; }

        char *start = p;
        while (*p != '\0' && *p != ' ' && *p != '.' && *p != '_' &&
               *p != '[' && *p != ']' && *p != '{' && *p != '}' &&
               *p != '(' && *p != ')')
            p++;

        toks[n].s = start;
        toks[n].len = (size_t)(p - start);
        toks[n].bracket = br > 0;
        toks[n].paren = pa > 0;
        n++;
    }
    return n;
}

static bool has_video_extension(const char *ext)
{
    static const char *const list[] = {
        "mkv", "mp4", "m4v", "avi", "mov", "wmv", "flv", "webm", "ts", "m2ts",
        "mts", "mpg", "mpeg", "ogv", "ogm", "divx", "3gp", "vob", "iso", NULL
    };
    char low[8];
    size_t n = strlen(ext);

    if (n == 0 || n >= sizeof(low))
        return false;
    for (size_t i = 0; i < n; i++)
        low[i] = (char)tolower((unsigned char)ext[i]);
    low[n] = '\0';
    return in_list(low, list);
}

/* Capitalise "the matrix of fire" -> "The Matrix of Fire" */
static void title_case(char *s)
{
    static const char *const small[] = {
        "a", "an", "the", "and", "or", "of", "in", "on", "at", "to", "for",
        "vs", "v", NULL
    };
    bool first = true;
    char *p = s;

    while (*p != '\0')
    {
        char *w = p;
        while (*p != '\0' && *p != ' ')
            p++;

        char saved = *p;
        *p = '\0';
        if (first || !in_list(w, small))
            *w = (char)toupper((unsigned char)*w);
        *p = saved;

        first = false;
        while (*p == ' ')
            p++;
    }
}

static bool has_upper(const char *s)
{
    for (; *s != '\0'; s++)
        if (isupper((unsigned char)*s))
            return true;
    return false;
}

static char *join_tokens(const struct token *toks, size_t count)
{
    size_t len = 1;
    for (size_t i = 0; i < count; i++)
        len += toks[i].len + 1;

    char *out = malloc(len);
    if (out == NULL)
        return NULL;

    char *o = out;
    for (size_t i = 0; i < count; i++)
    {
        if (i > 0)
            *o++ = ' ';
        memcpy(o, toks[i].s, toks[i].len);
        o += toks[i].len;
    }
    *o = '\0';
    return out;
}

static void trim_trailing_junk(char *s)
{
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '-' || s[n - 1] == ':' ||
                     s[n - 1] == ',' || s[n - 1] == '&'))
        s[--n] = '\0';
}

int vlc_release_name_parse(const char *name, struct vlc_release_info *info)
{
    char buf[MAX_NAME];
    struct token toks[MAX_TOKENS];
    const int maxyear = max_year();

    memset(info, 0, sizeof(*info));
    info->title = NULL;

    if (name == NULL)
        return -1;

    /* work on a bounded copy, without a known video extension */
    strncpy(buf, name, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char *dot = strrchr(buf, '.');
    if (dot != NULL && has_video_extension(dot + 1))
        *dot = '\0';

    /* the original (extension stripped), used when this is not a release name */
    char *plain = strdup(buf);
    if (plain == NULL)
        return -1;

    /* drop leading site / group tags: "[YTS.MX] Title", "www.site.com - Title" */
    char *start = buf;
    while (*start == ' ')
        start++;
    if (*start == '[' || *start == '{')
    {
        char *close = strchr(start, *start == '[' ? ']' : '}');
        if (close != NULL)
        {
            char *rest = close + 1;
            while (*rest == ' ' || *rest == '-' || *rest == '_' || *rest == '.')
                rest++;
            if (*rest != '\0')
                start = rest;
        }
    }
    else if (!strncasecmp(start, "www.", 4))
    {
        char *dash = strstr(start, " - ");
        if (dash != NULL && dash[3] != '\0')
            start = dash + 3;
    }

    size_t n = tokenize(start, toks, MAX_TOKENS);
    if (n == 0)
    {
        info->title = plain;
        return -1;
    }

    /* first strong marker */
    size_t first_strong = n;
    for (size_t i = 1; i < n; i++)
        if (is_strong(toks, n, i, maxyear))
        {
            first_strong = i;
            break;
        }

    /* season / episode, resolution */
    bool is_tv = false;
    for (size_t i = 1; i < n; i++)
    {
        struct lowtok l;
        int s, e;
        tok_lower(&toks[i], &l);
        if (l.base[0] == '\0')
            continue;
        if (!is_tv && !toks[i].bracket && !toks[i].paren &&
            parse_season_episode(&l, &s, &e) != 0)
        {
            info->season = s;
            info->episode = e;
            is_tv = true;
        }
        if (info->resolution[0] == '\0' && is_resolution(&l))
        {
            if (!strcmp(l.base, "uhd") || !strcmp(l.base, "4k"))
                strcpy(info->resolution, "4K");
            else if (!strcmp(l.base, "8k"))
                strcpy(info->resolution, "8K");
            else
                snprintf(info->resolution, sizeof(info->resolution), "%.7s", l.base);
        }
    }

    /* year: the last year-like word before the first marker (words at index 0
     * are the title: "1917", "2012"); otherwise a (2005) / [2005] anywhere */
    size_t year_idx = n;
    for (size_t i = 1; i < first_strong; i++)
        if (tok_is_year(&toks[i], maxyear))
            year_idx = i;
    if (year_idx == n)
        for (size_t i = 1; i < n; i++)
            if (tok_is_year(&toks[i], maxyear) && (toks[i].paren || toks[i].bracket))
            {
                year_idx = i;
                break;
            }
    if (year_idx != n)
        info->year = atoi(toks[year_idx].s);

    size_t end = first_strong < year_idx ? first_strong : year_idx;

    bool is_release = (end < n) || is_tv || info->resolution[0] != '\0';
    if (!is_release || end == 0)
    {
        /* a plain human title: only turn "some.dotted.name" into words */
        memset(info, 0, sizeof(*info));
        if (strchr(plain, ' ') == NULL)
            for (char *c = plain; *c != '\0'; c++)
                if (*c == '.' || *c == '_')
                    *c = ' ';
        info->title = plain;
        return -1;
    }
    free(plain);

    /* trim edition words and dashes at the end of the title */
    while (end > 1)
    {
        struct lowtok l;
        tok_lower(&toks[end - 1], &l);
        if (is_edition(&l) || (toks[end - 1].len == 1 && toks[end - 1].s[0] == '-'))
            end--;
        else
            break;
    }

    char *title = join_tokens(toks, end);
    if (title == NULL)
        return -1;
    trim_trailing_junk(title);
    if (title[0] == '\0')
    {
        free(title);
        title = strdup(name);
        if (title == NULL)
            return -1;
    }
    if (!has_upper(title))
        title_case(title);

    info->title = title;
    return 0;
}

void vlc_release_info_clean(struct vlc_release_info *info)
{
    free(info->title);
    info->title = NULL;
}

char *vlc_release_name_display(const char *name)
{
    struct vlc_release_info info;
    char *out = NULL;

    vlc_release_name_parse(name, &info);
    if (info.title == NULL)
        return NULL;

    if (info.season > 0 && info.episode > 0)
    {
        if (asprintf(&out, "%s - S%02dE%02d", info.title, info.season, info.episode) < 0)
            out = NULL;
    }
    else if (info.season > 0)
    {
        if (asprintf(&out, "%s - Season %d", info.title, info.season) < 0)
            out = NULL;
    }
    else if (info.year > 0)
    {
        if (asprintf(&out, "%s (%d)", info.title, info.year) < 0)
            out = NULL;
    }
    else
    {
        out = info.title;
        info.title = NULL;
    }

    vlc_release_info_clean(&info);
    return out;
}
