/*****************************************************************************
 * specific.c: Win32 specific initialization
 *****************************************************************************
 * Copyright (C) 2001-2004, 2010 VLC authors and VideoLAN
 *
 * Authors: Samuel Hocevar <sam@zoy.org>
 *          Gildas Bazin <gbazin@videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#ifndef UNICODE
# define UNICODE
#endif
#include <vlc_common.h>
#include "../libvlc.h"
#include "../lib/libvlc_internal.h"

#include <winsock2.h>

static int system_InitWSA(int hi, int lo)
{
    WSADATA data;

    if (WSAStartup(MAKEWORD(hi, lo), &data) == 0)
    {
        if (LOBYTE(data.wVersion) == 2 && HIBYTE(data.wVersion) == 2)
            return 0;
        /* Winsock DLL is not usable */
        WSACleanup( );
    }
    return -1;
}

/**
 * Initializes Winsock.
 */
void system_Init(void)
{
    if (system_InitWSA(2, 2) && system_InitWSA(1, 1))
        fputs("Error: cannot initialize Winsocks\n", stderr);
}

/*****************************************************************************
 * system_Configure: check for system specific configuration options.
 *****************************************************************************/

/* Must be same as in modules/control/win_msg.c */
typedef struct
{
    int argc;
    int enqueue;
    char data[];
} vlc_ipc_data_t;

#define VLC_IPC_NAME L"VLCFlix ipc " TEXT(VERSION)

/* Hands the command line to the running instance. Returns true once that instance
 * took it; false when it did not answer, which means it is on its way out. */
static bool SendToRunningInstance( libvlc_int_t *p_this, HWND ipcwindow,
                                   int i_argc, const char *const ppsz_argv[] )
{
    vlc_ipc_data_t *p_data;
    size_t i_data = sizeof (*p_data);

    for( int i_opt = 0; i_opt < i_argc; i_opt++ )
    {
        i_data += sizeof (size_t);
        i_data += strlen( ppsz_argv[ i_opt ] ) + 1;
    }

    p_data = malloc( i_data );
    if( unlikely(p_data == NULL) )
        return false;
    p_data->argc = i_argc;
    p_data->enqueue = var_InheritBool( p_this, "playlist-enqueue" );
    size_t i_pos = 0;
    for( int i_opt = 0; i_opt < i_argc; i_opt++ )
    {
        size_t i_len = strlen( ppsz_argv[ i_opt ] ) + 1;
        memcpy( &p_data->data[i_pos], &i_len, sizeof (size_t) );
        i_pos += sizeof (size_t);
        memcpy( &p_data->data[i_pos], ppsz_argv[ i_opt ], i_len );
        i_pos += i_len;
    }

    /* the running instance raises its window when asked to; Windows only lets it
     * take the foreground if the process the user just started allows it */
    DWORD pid;
    if( GetWindowThreadProcessId( ipcwindow, &pid ) )
        AllowSetForegroundWindow( pid );

    COPYDATASTRUCT wm_data;
    wm_data.dwData = 0;
    wm_data.cbData = i_data;
    wm_data.lpData = p_data;
    DWORD_PTR result = FALSE;
    LRESULT sent = SendMessageTimeout( ipcwindow, WM_COPYDATA, 0, (LPARAM)&wm_data,
                                       SMTO_ABORTIFHUNG | SMTO_BLOCK, 5000, &result );
    free( p_data );
    return sent != 0 && result == TRUE;
}

void system_Configure( libvlc_int_t *p_this, int i_argc, const char *const ppsz_argv[] )
{
#if WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP)
    if( var_InheritBool( p_this, "one-instance" )
     || ( var_InheritBool( p_this, "one-instance-when-started-from-file" )
       && var_InheritBool( p_this, "started-from-file" ) ) )
    {
        msg_Info( p_this, "one instance mode ENABLED");

        /* flix: the mutex lives exactly as long as the process that created it, the
         * IPC window only as long as its interface. An instance that is closing has
         * already lost the window but still holds the mutex (and the media library).
         * This used to give up right there and start a full second instance, which
         * then fought the closing one for the library database - and a closing
         * instance that hung kept doing that to every later launch, double-clicks
         * included. Now a launch waits for such an instance to be gone (the front end
         * makes sure that takes seconds, see bin/winvlc.c), then takes over. */
        const vlc_tick_t deadline = vlc_tick_now() + VLC_TICK_FROM_SEC(20);
        bool waited = false;

        for( ;; )
        {
            /* Use a named mutex to check if another instance is already running */
            HANDLE hmutex = CreateMutex( 0, TRUE, VLC_IPC_NAME );
            if( hmutex == NULL )
            {
                /* Failed for some reason. Just ignore the option and go on as
                 * normal. */
                msg_Err( p_this, "one instance mode DISABLED "
                         "(mutex couldn't be created)" );
                return;
            }

            if( GetLastError() != ERROR_ALREADY_EXISTS )
            {
                if( waited )
                    msg_Info( p_this, "previous instance is gone, taking over" );
                libvlc_InternalAddIntf( p_this, "win_msg,none" );
                /* Initialization done.
                 * Release the mutex to unblock other instances */
                ReleaseMutex( hmutex );
                return; /* the handle stays open for the life of the process */
            }

            /* Another instance is running: wait until it is initialized */
            DWORD wait = WaitForSingleObject( hmutex, 5000 );
            bool owned = wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED;

            /* Locate the window created by the IPC helper thread of the
             * 1st instance */
            HWND ipcwindow = owned ? FindWindow( 0, VLC_IPC_NAME ) : NULL;
            if( ipcwindow != NULL
             && SendToRunningInstance( p_this, ipcwindow, i_argc, ppsz_argv ) )
            {
                /* Initialization done.
                 * Release the mutex to unblock other instances */
                ReleaseMutex( hmutex );
                CloseHandle( hmutex );

                /* Bye bye */
                system_End( );
                exit( 0 );
            }

            if( owned )
                ReleaseMutex( hmutex );
            CloseHandle( hmutex );

            if( vlc_tick_now() >= deadline )
            {
                msg_Err( p_this, "one instance mode DISABLED "
                         "(the previous instance did not close)" );
                return;
            }
            if( !waited )
                msg_Info( p_this, "waiting for the previous instance to close" );
            waited = true;
            Sleep( 200 );
        }
    }
#else
    VLC_UNUSED(p_this); VLC_UNUSED(i_argc); VLC_UNUSED(ppsz_argv);
#endif
}

/**
 * Cleans up after system_Init() and system_Configure().
 */
void system_End(void)
{
    /* XXX: In theory, we should not call this if WSAStartup() failed. */
    WSACleanup();
}
