/*****************************************************************************
 * extension_thread.c: Extensions Manager, Threads manager (no Lua here)
 *****************************************************************************
 * Copyright (C) 2009-2010 VideoLAN and authors
 *
 * Authors: Jean-Philippe André < jpeg # videolan.org >
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "vlc.h"
#include "extension.h"
#include "assert.h"

#include <vlc_common.h>
#include <vlc_messages.h>
#include <vlc_player.h>

struct thread_sys_t
{
    extensions_manager_t *p_mgr;
    extension_t *p_ext;
};

/** Thread Run */
static void* Run( void *data );
static void FreeCommands( struct command_t *command );

/**
 * Player listeners
 */

static void
OnCurrentMediaChanged(vlc_player_t *player,
                      input_item_t *new_media,
                      void *opaque)
{
    (void)player;
    extension_t *ext = opaque;
    struct lua_extension *sys = ext->p_sys;

    vlc_mutex_lock(&sys->running_lock);
    // Change input
    input_item_t *old = sys->p_item;
    if (old)
        input_item_Release(old);

    if (new_media)
        input_item_Hold(new_media);
    sys->p_item = new_media;

    // Tell the script the input changed
    if (sys->i_capabilities & EXT_INPUT_LISTENER)
        PushCommandUnique(ext, CMD_SET_INPUT);
    vlc_mutex_unlock(&sys->running_lock);
}

/**
 * Activate an extension
 * @param p_ext Extension to activate
 * @return The usual VLC return codes
 **/
int Activate(extension_t *p_ext)
{
    assert( p_ext != NULL );

    struct lua_extension *sys = p_ext->p_sys;
    assert(sys != NULL);
    extensions_manager_t *mgr = sys->p_mgr;

    vlc_mutex_lock(&sys->command_lock);
    /* flix: b_exiting means the thread has been asked to finish. Treating a thread
     * that is on its way out as running is what let a half-dead extension swallow
     * commands: b_thread_running can still be true at this point, so the command is
     * queued and signalled into a thread that is on its last iteration and will never
     * read it. Once Run() marks itself done on its way out this resolves itself, and
     * the check here covers the window in between. */
    const bool thread_live = sys->b_thread_running && !sys->b_exiting;

    /* The previous thread was told to finish but has not returned yet - it can still
     * be inside Lua after the watch timer gave up on it - and it owns the Lua state
     * until it does. Starting another thread now would put two threads on one state.
     * Waiting for it here would freeze the interface, so refuse; the next attempt
     * after it has gone succeeds. */
    if (sys->b_thread_running && sys->b_exiting && !sys->b_thread_done)
    {
        vlc_mutex_unlock(&sys->command_lock);
        vlc_debug(p_ext->logger, "Extension '%s' is still shutting down",
                  p_ext->psz_title);
        return VLC_EGENERIC;
    }

    /* An activation is already on its way to a thread that can act on it. */
    if (sys->b_activating && thread_live)
    {
        vlc_mutex_unlock(&sys->command_lock);
        return VLC_SUCCESS;
    }

    /* Queue an activation unless one is already waiting to be picked up. Leaving a
     * command behind is deliberate when the thread is being restarted: the new thread
     * finds it there and runs it, which is exactly what is wanted. */
    if (sys->command == NULL && !sys->b_activated)
    {
        sys->command = calloc(1, sizeof(*sys->command));
        if (!sys->command)
        {
            vlc_mutex_unlock(&sys->command_lock);
            return VLC_ENOMEM;
        }
        sys->command->i_command = CMD_ACTIVATE; /* No params */
    }
    sys->b_activating = true;
    if (thread_live)
    {
        vlc_debug(p_ext->logger, "Reactivating extension %s", p_ext->psz_title);
        vlc_cond_signal(&sys->wait);
    }
    vlc_mutex_unlock(&sys->command_lock);

    if (!thread_live)
    {
        vlc_debug(p_ext->logger, "Activating extension '%s'", p_ext->psz_title);
        /* A thread that ended on its own is still waiting to be joined. It has
         * returned already (see the check above), so this does not block. */
        if (sys->b_thread_running)
        {
            vlc_join(sys->thread, NULL);
            sys->b_thread_running = false;
        }
        sys->b_thread_done = false;
        sys->b_exiting = false;
        if (vlc_clone(&sys->thread, Run, p_ext) != VLC_SUCCESS)
        {
            sys->b_exiting = true;
            return VLC_ENOMEM;
        }
        sys->b_thread_running = true;
    }

    /* Setup the listeners on the player object. */
    static const struct vlc_player_cbs player_cbs =
    {
        .on_current_media_changed = OnCurrentMediaChanged,
    };

    vlc_player_Lock(mgr->player);
    /* flix: an extension the watch timer killed never went through
     * QueueDeactivateCommand(), so its listener is still registered. Now that it can
     * be started again, drop that one first rather than add a second. */
    if (sys->player_listener != NULL)
        vlc_player_RemoveListener(mgr->player, sys->player_listener);
    sys->player_listener =
        vlc_player_AddListener(mgr->player, &player_cbs, p_ext);
    vlc_player_Unlock(mgr->player);

    if (sys->player_listener == NULL)
        goto error_listener;

    return VLC_SUCCESS;
error_listener:
    vlc_mutex_lock(&sys->command_lock);
    sys->b_exiting = true;
    vlc_cond_signal(&sys->wait);
    vlc_mutex_unlock(&sys->command_lock);
    vlc_join(sys->thread, NULL);
    sys->b_thread_running = false; /* joined: neither Activate() nor Close() may join again */
    return VLC_ENOMEM;
}

static void FreeCommands( struct command_t *command )
{
    while (command) {
        struct command_t *next = command->next;
        switch( command->i_command )
        {
            case CMD_ACTIVATE:
            case CMD_DEACTIVATE:
            case CMD_CLICK:
                /* No extra memory to free */
                break;
            case CMD_TRIGGERMENU:
            case CMD_PLAYING_CHANGED:
                free( command->data[0] ); // free allocated data
                break;
            default:
                break;
        }
        free(command);
        command = next;
    }
}

bool QueueDeactivateCommand( extension_t *p_ext )
{
    struct lua_extension *sys = p_ext->p_sys;
    vlc_mutex_assert(&sys->command_lock);

    struct command_t *cmd = calloc( 1, sizeof( struct command_t ) );
    if( unlikely( cmd == NULL ) )
        return false;
    /* Free the list of commands */
    if (sys->command != NULL)
        FreeCommands(sys->command->next);

    /* Push command */

    cmd->i_command = CMD_DEACTIVATE;
    if (sys->command)
        sys->command->next = cmd;
    else
        sys->command = cmd;

    sys->b_deactivating = true;
    sys->b_activating = false;
    vlc_cond_signal(&sys->wait);

    vlc_player_Lock(sys->p_mgr->player);
    if (sys->player_listener != NULL)
        vlc_player_RemoveListener(sys->p_mgr->player, sys->player_listener);
    sys->player_listener = NULL;
    vlc_player_Unlock(sys->p_mgr->player);

    return true;
}

/** Deactivate this extension: pushes immediate command and drops queued */
int Deactivate( extensions_manager_t *p_mgr, extension_t *p_ext )
{
    struct lua_extension *sys = p_ext->p_sys;

    vlc_mutex_lock(&sys->command_lock);
    if (!sys->b_activated && !sys->b_activating)
    {
        vlc_mutex_unlock(&sys->command_lock);
        return VLC_SUCCESS;
    }

    if (sys->b_exiting)
    {
        vlc_mutex_unlock(&sys->command_lock);
        return VLC_EGENERIC;
    }

    if (sys->p_progress_id != NULL)
    {
        // Extension is stuck, kill it now
        vlc_dialog_release(p_mgr, sys->p_progress_id);
        sys->p_progress_id = NULL;
        KillExtension(p_ext);
        vlc_mutex_unlock(&sys->command_lock);
        return VLC_SUCCESS;
    }

    bool b_success = QueueDeactivateCommand( p_ext );
    vlc_mutex_unlock(&sys->command_lock);

    return b_success ? VLC_SUCCESS : VLC_ENOMEM;
}

/* MUST be called with command_lock held */
void KillExtension(extension_t *p_ext)
{
    struct lua_extension *sys = p_ext->p_sys;
    vlc_debug(p_ext->logger, "Killing extension now");
    vlclua_fd_interrupt(&sys->dtable);
    sys->b_activated = false;
    sys->b_exiting = true;
    vlc_cond_signal(&sys->wait);
}

/** Push a UI command */
int PushCommand__( extension_t *p_ext,  bool b_unique, command_type_e i_command,
                   va_list args )
{
    struct lua_extension *sys = p_ext->p_sys;
    /* Create command */
    struct command_t *cmd = calloc( 1, sizeof( struct command_t ) );
    if( unlikely( cmd == NULL ) )
        return VLC_ENOMEM;
    cmd->i_command = i_command;
    switch( i_command )
    {
        case CMD_CLICK:
            cmd->data[0] = va_arg( args, void* );
            break;
        case CMD_TRIGGERMENU:
            {
                int *pi = malloc( sizeof( int ) );
                if( !pi )
                {
                    free( cmd );
                    return VLC_ENOMEM;
                }
                *pi = va_arg( args, int );
                cmd->data[0] = pi;
            }
            break;
        case CMD_PLAYING_CHANGED:
            {
                int *pi = malloc( sizeof( int ) );
                if( !pi )
                {
                    free( cmd );
                    return VLC_ENOMEM;
                }
                *pi = va_arg( args, int );
                cmd->data[0] = pi;
            }
            break;
        case CMD_CLOSE:
        case CMD_SET_INPUT:
        case CMD_UPDATE_META:
            // Nothing to do here
            break;
        default:
            msg_Dbg(sys->p_mgr, "Unknown command send to extension: %d",
                    i_command);
            break;
    }

    vlc_mutex_lock(&sys->command_lock);

    /* Push command to the end of the queue */
    struct command_t *last = sys->command;
    if( !last )
    {
        sys->command = cmd;
    }
    else
    {
        bool b_skip = false;
        while( last->next != NULL )
        {
            if( b_unique && last->i_command == i_command )
            {
                // Do not push this 'unique' command a second time
                b_skip = !memcmp( last->data, cmd->data, sizeof( cmd->data ) );
                break;
            }
            else
            {
                last = last->next;
            }
        }
        if( !b_skip )
        {
            last->next = cmd;
        }
        else
        {
            FreeCommands( cmd );
        }
    }

    vlc_cond_signal(&sys->wait);
    vlc_mutex_unlock(&sys->command_lock);
    return VLC_SUCCESS;
}

/* Thread loop */
static void* Run( void *data )
{
    extension_t *p_ext = data;
    struct lua_extension *sys = p_ext->p_sys;
    extensions_manager_t *p_mgr = sys->p_mgr;

    vlc_thread_set_name("vlc-lua-ext");

    vlc_mutex_lock(&sys->command_lock);

    while (!sys->b_exiting || (sys->command && sys->command->i_command == CMD_DEACTIVATE))
    {
        struct command_t *cmd = sys->command;

        /* Pop command in front */
        if( cmd == NULL )
        {
            vlc_cond_wait(&sys->wait, &sys->command_lock);
            continue;
        }
        sys->command = cmd->next;
        cmd->next = NULL; /* unlink command (for FreeCommands()) */
        // Create watch timer
        vlc_timer_schedule(sys->timer, false, WATCH_TIMER_PERIOD,
                           VLC_TIMER_FIRE_ONCE);
        vlc_mutex_unlock(&sys->command_lock);

        /* Run command */
        vlc_mutex_lock(&sys->running_lock);
        switch( cmd->i_command )
        {
            case CMD_ACTIVATE:
            {
                if( lua_ExecuteFunction( p_mgr, p_ext, "activate", LUA_END ) < 0 )
                {
                    msg_Err( p_mgr, "Could not activate extension!" );
                    vlc_mutex_lock(&sys->command_lock);
                    QueueDeactivateCommand( p_ext );
                    vlc_mutex_unlock(&sys->command_lock);
                    break;
                }
                vlc_mutex_lock(&sys->command_lock);
                sys->b_activated = true;
                sys->b_activating = false;
                vlc_mutex_unlock(&sys->command_lock);
                break;
            }

            case CMD_DEACTIVATE:
            {
                vlc_debug(p_ext->logger, "Deactivating '%s'", p_ext->psz_title);
                if( lua_ExtensionDeactivate( p_mgr, p_ext ) < 0 )
                {
                    vlc_warning(p_ext->logger, "Extension '%s' did not deactivate properly",
                                p_ext->psz_title);
                }
                vlc_mutex_lock(&sys->command_lock);
                sys->b_activated = false;
                sys->b_deactivating = false;
                vlc_mutex_unlock(&sys->command_lock);
                break;
            }

            case CMD_CLOSE:
            {
                lua_ExecuteFunction( p_mgr, p_ext, "close", LUA_END );
                break;
            }

            case CMD_CLICK:
            {
                extension_widget_t *p_widget = cmd->data[0];
                assert( p_widget );
                vlc_debug(p_ext->logger, "Clicking '%s': '%s'",
                         p_ext->psz_name, p_widget->psz_text);
                if( lua_ExtensionWidgetClick( p_mgr, p_ext, p_widget ) < 0 )
                    vlc_debug(p_ext->logger, "Could not translate click");
                break;
            }

            case CMD_TRIGGERMENU:
            {
                int *pi_id = cmd->data[0];
                assert( pi_id );
                vlc_debug(p_ext->logger, "Trigger menu %d of '%s'",
                          *pi_id, p_ext->psz_name);
                lua_ExtensionTriggerMenu( p_mgr, p_ext, *pi_id );
                break;
            }

            case CMD_SET_INPUT:
            {
                lua_ExecuteFunction( p_mgr, p_ext, "input_changed", LUA_END );
                break;
            }

            case CMD_UPDATE_META:
            {
                lua_ExecuteFunction( p_mgr, p_ext, "meta_changed", LUA_END );
                break;
            }

            case CMD_PLAYING_CHANGED:
            {
                lua_ExecuteFunction( p_mgr, p_ext, "playing_changed",
                        LUA_NUM, *((int *)cmd->data[0]), LUA_END );
                break;
            }

            default:
            {
                msg_Dbg( p_mgr, "Unknown command in extension command queue: %d",
                         cmd->i_command );
                break;
            }
        }
        vlc_mutex_unlock(&sys->running_lock);

        FreeCommands( cmd );

        vlc_mutex_lock(&sys->command_lock);
        // Reset watch timer and timestamp
        if (sys->p_progress_id != NULL)
        {
            vlc_dialog_release(p_mgr, sys->p_progress_id);
            sys->p_progress_id = NULL;
        }
        vlc_timer_disarm(sys->timer);
    }

    vlc_mutex_unlock(&sys->command_lock);
    msg_Dbg( p_mgr, "Extension thread end: '%s'", p_ext->psz_title );

    /* flix: say that we are gone. After the thread had ended once - the watch timer
     * killing a slow extension does it - every later Activate() queued a command and
     * signalled a condition variable that nothing was waiting on. The command was
     * never consumed, b_activating stayed set forever, and from then on activating the
     * extension did nothing at all: no window, no message, nothing. b_thread_done is
     * what lets Activate() join this thread and start a new one. b_thread_running is
     * left alone: it means "started and not joined yet", which is still true, and the
     * shutdown path relies on it to join. */
    vlc_mutex_lock(&sys->command_lock);
    sys->b_thread_done = true;
    sys->b_activating = false;
    sys->b_exiting = true;
    sys->b_activated = false;
    vlc_mutex_unlock(&sys->command_lock);

    // Note: At this point, the extension should be deactivated
    return NULL;
}
