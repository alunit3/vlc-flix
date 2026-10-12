/*****************************************************************************
 * main_interface.cpp : Main interface
 ****************************************************************************
 * Copyright (C) 2006-2011 VideoLAN and AUTHORS
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
 *          Ilkka Ollakka <ileoo@videolan.org>
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
 * along with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"

#include <QQmlEngine>
#include <QJSEngine>

#include "mainctx.hpp"
#include "mainctx_submodels.hpp"
#include "medialibrary/mlhelper.hpp"

#include "compositor.hpp"
#include "util/renderer_manager.hpp"
#include "util/csdbuttonmodel.hpp"

#include "util/vlchotkeyconverter.hpp"
#include "util/qt_dirs.hpp"                     // toNativeSeparators

#include "util/color_scheme_model.hpp"

#include "widgets/native/interface_widgets.hpp"     // bgWidget, videoWidget

#include "playlist/playlist_controller.hpp"
#include "player/player_controller.hpp"

#include <vlc_input_item.h>

#include "dialogs/dialogs_provider.hpp"
#include "dialogs/systray/systray.hpp"

#include "videosurface.hpp"

#include "menus/menus.hpp"                            // Menu creation

#include "dialogs/toolbar/controlbar_profile_model.hpp"
#include "dialogs/help/help.hpp"

#include <QKeyEvent>

#include <QUrl>
#include <QDate>
#include <QMimeData>
#include <QClipboard>
#include <QInputDialog>

#include <QQmlProperty>

#include <QWindow>
#include <QScreen>

#include <QOperatingSystemVersion>

#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
#include <QStyleHints>
#endif

#ifdef _WIN32
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QDirIterator>
#include <QSet>
#include <QJsonDocument>
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QDesktopServices>
#include <QDateTime>
#include <QFileDialog>
#include <QProcess>
#include <QTimer>
#include <QCoreApplication>
#include <QSettings>
#include <QRegularExpression>
#endif

#include <vlc_interface.h>
#include <vlc_preparser.h>
#include <vlc_strings.h>

#define VLC_REFERENCE_SCALE_FACTOR 96.

using  namespace vlc::playlist;

// #define DEBUG_INTF

/* Callback prototypes */
static int PopupMenuCB( vlc_object_t *p_this, const char *psz_variable,
                        vlc_value_t old_val, vlc_value_t new_val, void *param );
static int IntfShowCB( vlc_object_t *p_this, const char *psz_variable,
                       vlc_value_t old_val, vlc_value_t new_val, void *param );
static int IntfBossCB( vlc_object_t *p_this, const char *psz_variable,
                       vlc_value_t old_val, vlc_value_t new_val, void *param );
static int IntfRaiseMainCB( vlc_object_t *p_this, const char *psz_variable,
                           vlc_value_t old_val, vlc_value_t new_val,
                           void *param );
static int SubtitleOfferCB( vlc_object_t *p_this, const char *psz_variable,
                            vlc_value_t old_val, vlc_value_t new_val, void *param );
static int MetaUpdateCB( vlc_object_t *p_this, const char *psz_variable,
                         vlc_value_t old_val, vlc_value_t new_val, void *param );
static int AccountResultCB( vlc_object_t *p_this, const char *psz_variable,
                            vlc_value_t old_val, vlc_value_t new_val, void *param );
static int UpdateCB( vlc_object_t *p_this, const char *psz_variable,
                     vlc_value_t old_val, vlc_value_t new_val, void *param );

const QEvent::Type MainCtx::ToolbarsNeedRebuild =
        (QEvent::Type)QEvent::registerEventType();

namespace
{

template <typename T>
T loadVLCOption(vlc_object_t *obj, const char *name);

template <>
int loadVLCOption<int>(vlc_object_t *obj, const char *name)
{
    return var_InheritInteger(obj, name);
}

template <>
float loadVLCOption<float>(vlc_object_t *obj, const char *name)
{
    return var_InheritFloat(obj, name);
}

template <>
bool loadVLCOption<bool>(vlc_object_t *obj, const char *name)
{
    return var_InheritBool(obj, name);
}

}

MainCtx::MainCtx(qt_intf_t *_p_intf)
    : p_intf(_p_intf)
    , m_csdButtonModel {std::make_unique<CSDButtonModel>(this, this)}
{
    // If `playlist-autostart` is set, and there are initial files
    // we don't bother loading main display just to unload it
    // immediately after. Instead, we directly load the player
    // page:
    if (var_InheritBool(p_intf, "playlist-autostart"))
    {
        // We can not use `vlc_playlist_GetCurrentIndex()`, because
        // playlist starts playing after the interface is added.
        // We also can not use the playlist controller because it
        // is not updated yet.
        vlc_playlist_locker lock(p_intf->p_playlist);

        if (vlc_playlist_Count(p_intf->p_playlist) > 0)
        {
            m_mainInterfaceModes |= MAININTERFACE_MODE_PLAYER;
        }
    }

    /**
     *  Configuration and settings
     *  Pre-building of interface
     **/

    settings = getSettings();
    m_colorScheme = new ColorSchemeModel(this);

#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
    connect(m_colorScheme, &ColorSchemeModel::currentChanged, qGuiApp, [colorScheme = m_colorScheme]() {
        QStyleHints *const styleHints = qGuiApp->styleHints();
        if (unlikely(!styleHints))
            return;

        Qt::ColorScheme scheme;
        switch (colorScheme->currentScheme())
        {
        case ColorSchemeModel::ColorScheme::Day:
            scheme = Qt::ColorScheme::Light;
            break;
        case ColorSchemeModel::ColorScheme::Night:
            scheme = Qt::ColorScheme::Dark;
            break;
        case ColorSchemeModel::ColorScheme::System:
        default:
            styleHints->unsetColorScheme();
            return;
        }

        styleHints->setColorScheme(scheme);
    });
#endif

    m_sort = new SortCtx(this);
    m_search = new SearchCtx(this);
    m_playqueuePanel = new SidePanelCtx(this);
    m_navigationPanel = new SidePanelCtx(this);

    // getOSInfo();
    QOperatingSystemVersion currentOS = QOperatingSystemVersion::current();
    switch (currentOS.type()) {
    case QOperatingSystemVersion::OSType::Windows:
        m_osName = Windows;
        break;

    default:
        m_osName = Unknown;
        break;
    }
    m_osVersion = (currentOS.majorVersion());

    loadPrefs(false);
    loadFromSettingsImpl(false);

    /* Get the available interfaces */
    m_extraInterfaces = new VLCVarChoiceModel(VLC_OBJECT(p_intf->intf), "intf-add", this);

    vlc_medialibrary_t* ml = vlc_ml_instance_get( p_intf );
    b_hasMedialibrary = (ml != NULL);
    if (b_hasMedialibrary) {
        m_medialib = new MediaLib(p_intf, p_intf->p_mainPlaylistController);
    }

    /* Controlbar Profile Model Creation */
    m_controlbarProfileModel = new ControlbarProfileModel(p_intf->mainSettings, this);

    const QUrl homeUrl = QUrl::fromLocalFile(QVLCUserDir( VLC_HOME_DIR ));
    m_dialogFilepath = getSettings()->value( "filedialog-path", homeUrl ).toUrl();

    QString platformName = QGuiApplication::platformName();

    b_hasWayland = platformName.startsWith(QLatin1String("wayland"), Qt::CaseInsensitive);

    /*********************************
     * Create the Systray Management *
     *********************************/
    //postpone systray initialisation to speedup starting time
    QMetaObject::invokeMethod(this, &MainCtx::initSystray, Qt::QueuedConnection);

    /*************************************************************
     * Connect the input manager to the GUI elements it manages  *
     * Beware initSystray did some connects on input manager too *
     *************************************************************/
    /**
     * Connects on nameChanged()
     * Those connects are different because options can impeach them to trigger.
     **/
    /* Main Interface statusbar */
    /* and title of the Main Interface*/
    connect( THEMIM, &PlayerController::inputChanged, this, &MainCtx::onInputChanged );

    /* END CONNECTS ON IM */

    /* VideoWidget connects for asynchronous calls */
    connect( this, &MainCtx::askToQuit, THEDP, &DialogsProvider::quit, Qt::QueuedConnection  );

    /** END of CONNECTS**/


    /************
     * Callbacks
     ************/
    libvlc_int_t* libvlc = vlc_object_instance(p_intf);
    var_AddCallback( libvlc, "intf-toggle-fscontrol", IntfShowCB, p_intf );
    var_AddCallback( libvlc, "intf-boss", IntfBossCB, p_intf );
    var_AddCallback( libvlc, "intf-show", IntfRaiseMainCB, p_intf );
    var_AddCallback( libvlc, "flix-sub-offer", SubtitleOfferCB, p_intf );
    var_AddCallback( libvlc, "flix-meta-update", MetaUpdateCB, p_intf );
    var_AddCallback( libvlc, "flix-account-result", AccountResultCB, p_intf );
    var_AddCallback( libvlc, "flix-update", UpdateCB, p_intf );

    /* Register callback for the intf-popupmenu variable */
    var_AddCallback( libvlc, "intf-popupmenu", PopupMenuCB, p_intf );

    if( var_InheritBool( p_intf, "qt-privacy-ask") )
    {
        //postpone dialog call, as composition might not be ready yet
        QMetaObject::invokeMethod(this, [](){
            THEDP->firstRunDialog();
        }, Qt::QueuedConnection);
    }
    else if (m_medialib)
    {
        QMetaObject::invokeMethod(m_medialib, &MediaLib::reload, Qt::QueuedConnection);
    }

    const struct vlc_preparser_cfg cfg = []{
        struct vlc_preparser_cfg cfg{};
        cfg.types = VLC_PREPARSER_TYPE_PARSE;
        cfg.max_parser_threads = 1;
        cfg.timeout = 0;
        cfg.external_process = false;
        return cfg;
    }();
    m_network_preparser = vlc_preparser_New(VLC_OBJECT(libvlc), &cfg);

#ifdef UPDATE_CHECK
    /* Checking for VLC updates */
    if( var_InheritBool( p_intf, "qt-updates-notif" ) &&
        !var_InheritBool( p_intf, "qt-privacy-ask" ) )
    {
        int interval = var_InheritInteger( p_intf, "qt-updates-days" );
        if( QDate::currentDate() >
            getSettings()->value( "updatedate" ).toDate().addDays( interval ) )
        {
            /* check for update at startup */
            getUpdateModel()->checkUpdate();
            getSettings()->setValue( "updatedate", QDate::currentDate() );
        }
    }
#endif

    m_threadRunner = new ThreadRunner();

    m_initialEffectiveMainInterfaceMode = getEffectiveMainInterfaceMode();
}

MainCtx::~MainCtx()
{
    stopTorrent();
    if( m_webProc )
    {
        m_webProc->kill();
        m_webProc->waitForFinished( 500 );
    }
    if( m_filesProc )
    {
        m_filesProc->kill();
        m_filesProc->waitForFinished( 500 );
    }
    if( m_sourcesProc )
    {
        m_sourcesProc->kill();
        m_sourcesProc->waitForFinished( 500 );
    }
    /* Save states */

    m_threadRunner->destroy();

    if ( !p_intf->preferencesResetPending)
    {
        settings->beginGroup("MainWindow");
        settings->setValue( "ShowRemainingTime", m_showRemainingTime );
        settings->setValue( "interface-scale", QString::number( m_intfUserScaleFactor ) );

        /* Save playlist state */
        settings->setValue( "playqueue-panel-docked", m_playqueuePanel->m_docked );
        settings->setValue( "playqueue-panel-visible", m_playqueuePanel->m_visible );
        settings->setValue( "playqueue-panel-width", QString::number( m_playqueuePanel->m_width ) );

        settings->setValue( "navigation-panel-visible", m_navigationPanel->m_visible );
        settings->setValue( "navigation-panel-width", QString::number( m_navigationPanel->m_width ) );

        settings->setValue( "player-playlist-width", QString::number( m_playerPlaylistWidth ) );
        settings->setValue( "artist-albums-width", QString::number( m_artistAlbumsWidth ) );

        settings->setValue( "grid-view", m_gridView );
        settings->setValue( "grouping", m_grouping );

        settings->setValue( "color-scheme-index", m_colorScheme->currentIndex() );

        settings->setValue( "album-sections", m_albumSections );

        settings->setValue( "lyrics-mode", m_lyricsMode );

        /* Save the stackCentralW sizes */
        settings->endGroup();
    }
    else
    {
        settings->remove("MainWindow");
    }

    if( !p_intf->preferencesResetPending && var_InheritBool( p_intf, "save-recentplay" ) )
        getSettings()->setValue( "filedialog-path", m_dialogFilepath );
    else
        getSettings()->remove( "filedialog-path" );

    /* Unregister callbacks */
    libvlc_int_t* libvlc = vlc_object_instance(p_intf);
    var_DelCallback( libvlc, "intf-boss", IntfBossCB, p_intf );
    var_DelCallback( libvlc, "intf-show", IntfRaiseMainCB, p_intf );
    var_DelCallback( libvlc, "flix-sub-offer", SubtitleOfferCB, p_intf );
    var_DelCallback( libvlc, "flix-meta-update", MetaUpdateCB, p_intf );
    var_DelCallback( libvlc, "flix-account-result", AccountResultCB, p_intf );
    var_DelCallback( libvlc, "flix-update", UpdateCB, p_intf );
    var_DelCallback( libvlc, "intf-toggle-fscontrol", IntfShowCB, p_intf );
    var_DelCallback( libvlc, "intf-popupmenu", PopupMenuCB, p_intf );

    if (m_medialib)
        delete m_medialib;

    if (m_network_preparser)
        vlc_preparser_Delete(m_network_preparser);

    p_intf->p_mi = NULL;
}

bool MainCtx::hasVLM() const {
#ifdef ENABLE_VLM
    return true;
#else
    return false;
#endif
}

bool MainCtx::useClientSideDecoration() const
{
    //don't show CSD when interface is fullscreen
    return !m_windowTitlebar;
}

bool MainCtx::hasFirstrun() const {
    return var_InheritBool(p_intf,  "qt-privacy-ask" );
}

void MainCtx::setUseGlobalShortcuts( bool useShortcuts )
{
    if (m_useGlobalShortcuts == useShortcuts)
        return;
    m_useGlobalShortcuts = useShortcuts;
    emit useGlobalShortcutsChanged(m_useGlobalShortcuts);
}

void MainCtx::setWindowSuportExtendedFrame(bool support) {
    if (m_windowSuportExtendedFrame == support)
        return;
    m_windowSuportExtendedFrame = support;
    emit windowSuportExtendedFrameChanged();
}

void MainCtx::setWindowExtendedMargin(unsigned int margin) {
    if (margin == m_windowExtendedMargin)
        return;
    m_windowExtendedMargin = margin;
    emit windowExtendedMarginChanged(margin);
}

/*****************************
 *   Main UI handling        *
 *****************************/

void MainCtx::loadPrefs(const bool callSignals)
{
    const auto loadFromVLCOption = [this, callSignals](auto &variable, const char *name
            , const std::function<void(MainCtx *)> signal)
    {
        using variableType = std::remove_reference_t<decltype(variable)>;

        const auto value =  loadVLCOption<variableType>(VLC_OBJECT(p_intf), name);
        if (value == variable)
            return;

        variable = value;
        if (callSignals && signal)
            signal(this);
    };

    bool minimalMode = false;
    /* Are we in the enhanced always-video mode or not ? */
    loadFromVLCOption(minimalMode, "qt-minimal-view", nullptr);
    setMinimalView(minimalMode);

    loadFromVLCOption(m_bgCone, "qt-bgcone", &MainCtx::bgConeToggled);

    /* Should the UI stays on top of other windows */
    loadFromVLCOption(b_interfaceOnTop, "video-on-top", [this](MainCtx *)
    {
        emit interfaceAlwaysOnTopChanged(b_interfaceOnTop);
    });

    loadFromVLCOption(m_hasToolbarMenu, "qt-menubar", &MainCtx::hasToolbarMenuChanged);

    loadFromVLCOption(m_windowTitlebar, "qt-titlebar" , &MainCtx::useClientSideDecorationChanged);

    loadFromVLCOption(m_smoothScroll, "qt-smooth-scrolling", &MainCtx::smoothScrollChanged);

    loadFromVLCOption(m_maxVolume, "qt-max-volume", &MainCtx::maxVolumeChanged);

    loadFromVLCOption(m_pinVideoControls, "qt-pin-controls", &MainCtx::pinVideoControlsChanged);

    loadFromVLCOption(m_pinOpacity, "qt-fs-opacity", &MainCtx::pinOpacityChanged);

    loadFromVLCOption(m_safeArea, "qt-safe-area", &MainCtx::safeAreaChanged);

    loadFromVLCOption(m_mouseHideTimeout, "mouse-hide-timeout", &MainCtx::mouseHideTimeoutChanged);
}

void MainCtx::loadFromSettingsImpl(const bool callSignals)
{
    const auto loadFromSettings = [this, callSignals](auto &variable, const char *name
            , const auto defaultValue, auto obj,  auto signal)
    {
        using variableType = std::remove_reference_t<decltype(variable)>;

        const auto value = getSettings()->value(name, defaultValue).template value<variableType>();
        if (value == variable)
            return;

        variable = value;
        if (obj && callSignals && signal)
            (obj->*signal)(variable);
    };

    loadFromSettings(m_playqueuePanel->m_docked, "MainWindow/playqueue-panel-docked", true, m_playqueuePanel, &SidePanelCtx::dockedChanged);
    loadFromSettings(m_playqueuePanel->m_visible, "MainWindow/playqueue-panel-visible", false, m_playqueuePanel, &SidePanelCtx::visibleChanged);
    loadFromSettings(m_playqueuePanel->m_width, "MainWindow/playqueue-panel-width", 120, m_playqueuePanel, &SidePanelCtx::widthChanged);

    loadFromSettings(m_navigationPanel->m_visible, "MainWindow/navigation-panel-visible", true, m_navigationPanel, &SidePanelCtx::visibleChanged);
    loadFromSettings(m_navigationPanel->m_width, "MainWindow/navigation-panel-width", 120, m_navigationPanel, &SidePanelCtx::widthChanged);

    loadFromSettings(m_playerPlaylistWidth, "MainWindow/player-playlist-width", 120, this, &MainCtx::playerPlaylistWidthChanged);
    loadFromSettings(m_artistAlbumsWidth, "MainWindow/artist-albums-width", 120, this,  &MainCtx::artistAlbumsWidthChanged);

    loadFromSettings(m_gridView, "MainWindow/grid-view", true, this, &MainCtx::gridViewChanged);

    loadFromSettings(m_grouping, "MainWindow/grouping", GROUPING_NONE, this, &MainCtx::groupingChanged);

    loadFromSettings(m_showRemainingTime, "MainWindow/ShowRemainingTime", false, this, &MainCtx::showRemainingTimeChanged);

    loadFromSettings(m_albumSections, "MainWindow/album-sections", true, this, &MainCtx::albumSectionsChanged);

    loadFromSettings(m_lyricsMode, "MainWindow/lyrics-mode", true, this, &MainCtx::lyricsModeChanged);

    // flix: default to the Night scheme (index 2) instead of System
    const auto colorSchemeIndex = getSettings()->value( "MainWindow/color-scheme-index", 2 ).toInt();
    m_colorScheme->setCurrentIndex(colorSchemeIndex);

    /* user interface scale factor */
    auto userIntfScaleFactor = var_InheritFloat(p_intf, "qt-interface-scale");
    if (userIntfScaleFactor == -1)
        userIntfScaleFactor = getSettings()->value( "MainWindow/interface-scale", 1.0).toDouble();
    if (m_intfUserScaleFactor != userIntfScaleFactor)
    {
        m_intfUserScaleFactor = userIntfScaleFactor;
        updateIntfScaleFactor();
    }
}

void MainCtx::reloadPrefs()
{
    loadPrefs(true);
}

void MainCtx::onInputChanged( bool hasInput )
{
    // flix: torrent data is only really in use while our own stream is the thing
    // playing. Ask the playlist rather than the helper process: the helper watches
    // this process and stays alive until we stop it, so its existence says nothing.
    const bool wasTorrentActive = m_torrentActive;
    if( m_streamProc )
        setTorrentActive( hasInput && playingTorrentStream() );

    /* Our stream stopped being what plays: the player let go of it, or something else -
     * a local film - took its place. The torrent helper watches this process (not the
     * player) to know when to quit, so it would otherwise outlive the stream: seeding in
     * the background, its stats drawn over the next film and the storage page refusing to
     * clear its data. Wait a moment first, because starting another title brings its own
     * input and would otherwise cancel the stop.
     *
     * The generation is the *torrent* one, not the input one. It used to be bumped
     * by every new input, which meant playing a local film in the two seconds after
     * a stream ended cancelled the stop: the helper kept seeding and its data dir
     * stayed put, so the storage page said "in use by the current stream" for a
     * stream that had not run for hours. Only a new torrent should cancel this.
     *
     * Only arm the stop when it was the current torrent's own stream that went away.
     * Switching torrents stops the old helper first, so the old stream fails and
     * its input goes away *after* the new torrent has started: armed then, the
     * stop would carry the new generation and kill the helper that was just
     * launched. torrentStart() clears the active flag before that happens, which is
     * what tells the two cases apart. */
    if( wasTorrentActive && !m_torrentActive )
    {
        const quint64 gen = m_torrentGeneration;
        QTimer::singleShot( 2000, this, [this, gen]() {
            if( m_torrentGeneration == gen && !playingTorrentStream() )
                stopTorrent();
        } );
    }

    if( hasInput == false )
        return;
    int autoRaise = var_InheritInteger( p_intf, "qt-auto-raise" );
    if ( autoRaise == MainCtx::RAISE_NEVER )
        return;
    if( THEMIM->hasVideoOutput() == true )
    {
        if( ( autoRaise & MainCtx::RAISE_VIDEO ) == 0 )
            return;
    }
    else if ( ( autoRaise & MainCtx::RAISE_AUDIO ) == 0 )
        return;
    emit askRaise();
}

// true when the item that is playing is the one the helper is serving
bool MainCtx::playingTorrentStream() const
{
    PlayerController *pc = p_intf->p_mainPlayerController;
    if( pc == nullptr )
        return false;
    input_item_t *input = pc->getInput();
    if( input == nullptr )
        return false;
    char *uri = input_item_GetURI( input );
    if( uri == nullptr )
        return false;
    const bool ours = strncmp( uri, "http://127.0.0.1", 16 ) == 0;
    free( uri );
    return ours;
}

#ifdef KeyPress
#undef KeyPress
#endif
void MainCtx::sendHotkey(Qt::Key key , Qt::KeyboardModifiers modifiers)
{
    QKeyEvent event(QEvent::KeyPress, key, modifiers );
    int vlckey = qtEventToVLCKey(&event);
    var_SetInteger(vlc_object_instance(p_intf), "key-pressed", vlckey);
}

void MainCtx::sendVLCHotkey(int vlcHotkey)
{
    var_SetInteger(vlc_object_instance(p_intf), "key-pressed", vlcHotkey);
}

void MainCtx::updateIntfScaleFactor()
{
    auto newValue = m_intfUserScaleFactor;
    if (QWindow* window = p_intf->p_compositor ? p_intf->p_compositor->interfaceMainWindow() : nullptr)
    {
        QScreen* screen = window->screen();
        if (screen)
        {
            qreal dpi = screen->logicalDotsPerInch();
            newValue = m_intfUserScaleFactor * dpi / VLC_REFERENCE_SCALE_FACTOR;
        }
    }

    const int FACTOR_RESOLUTION = 100;
    if ( static_cast<int>(m_intfScaleFactor * FACTOR_RESOLUTION)
         == static_cast<int>(newValue * FACTOR_RESOLUTION) ) return;

    m_intfScaleFactor = newValue;
    emit intfScaleFactorChanged();
}

void MainCtx::onWindowVisibilityChanged(QWindow::Visibility visibility)
{
    m_windowVisibility = visibility;
}

void MainCtx::setHasAcrylicSurface(const bool v)
{
    if (m_hasAcrylicSurface == v)
        return;

    m_hasAcrylicSurface = v;
    emit hasAcrylicSurfaceChanged(v);
}

void MainCtx::incrementIntfUserScaleFactor(bool increment)
{
    if (increment)
        setIntfUserScaleFactor(m_intfUserScaleFactor + 0.1);
    else
        setIntfUserScaleFactor(m_intfUserScaleFactor - 0.1);
}

void MainCtx::setIntfUserScaleFactor(double newValue)
{
    const auto value = qBound(getMinIntfUserScaleFactor(), newValue, getMaxIntfUserScaleFactor());
    if (qFuzzyCompare(value, m_intfUserScaleFactor))
        return;
    m_intfUserScaleFactor = value;
    updateIntfScaleFactor();
}

void MainCtx::setHasToolbarMenu( bool hasToolbarMenu )
{
    if (m_hasToolbarMenu == hasToolbarMenu)
        return;

    m_hasToolbarMenu = hasToolbarMenu;

    config_PutInt("qt-menubar", (int) hasToolbarMenu);

    emit hasToolbarMenuChanged();
}

void MainCtx::setPinVideoControls(bool pinVideoControls)
{
    if (m_pinVideoControls == pinVideoControls)
        return;

    m_pinVideoControls = pinVideoControls;
    emit pinVideoControlsChanged();
}

void MainCtx::setPinOpacity(float pinOpacity)
{
    if (m_pinOpacity == pinOpacity)
        return;

    m_pinOpacity = pinOpacity;

    emit pinOpacityChanged();
}

inline void MainCtx::initSystray()
{
    bool b_systrayAvailable = QSystemTrayIcon::isSystemTrayAvailable();
    bool b_systrayWanted = var_InheritBool( p_intf, "qt-system-tray" );

    if( var_InheritBool( p_intf, "qt-start-minimized") )
    {
        if( b_systrayAvailable )
        {
            b_systrayWanted = true;
            b_hideAfterCreation = true;
        }
        else
            msg_Err( p_intf, "cannot start minimized without system tray bar" );
    }

    if( b_systrayAvailable && b_systrayWanted )
        m_systray = std::make_unique<VLCSystray>(this);
}

ThreadRunner* MainCtx::threadRunner() const
{
    return m_threadRunner;
}

QUrl MainCtx::folderMRL(const QString &fileMRL) const
{
    return folderMRL(QUrl::fromUserInput(fileMRL));
}

QUrl MainCtx::folderMRL(const QUrl &fileMRL) const
{
    if (fileMRL.isLocalFile())
    {
        const QString f = fileMRL.toLocalFile();
        return QUrl::fromLocalFile(QFileInfo(f).absoluteDir().absolutePath());
    }

    return {};
}

QString MainCtx::displayMRL(const QUrl &mrl) const
{
    return urlToDisplayString(mrl);
}

QVariantMap MainCtx::releaseInfo(const QString &name) const
{
    struct vlc_release_info info;
    const bool recognized = (vlc_release_name_parse(qtu(name), &info) == 0);

    QVariantMap map;
    map.insert(QStringLiteral("recognized"), recognized);
    map.insert(QStringLiteral("title"), info.title ? qfu(info.title) : name);
    map.insert(QStringLiteral("year"), info.year);
    map.insert(QStringLiteral("season"), info.season);
    map.insert(QStringLiteral("episode"), info.episode);
    map.insert(QStringLiteral("resolution"), qfu(info.resolution));
    map.insert(QStringLiteral("isEpisode"), info.season > 0);

    vlc_release_info_clean(&info);
    return map;
}

// the cache is split by source so test servers can never mix with the real TMDB data
static QString metaDirectory( qt_intf_t *intf )
{
    char *dir = config_GetUserDir( VLC_USERDATA_DIR );
    if( dir == nullptr )
        return QString();
    char *base = var_InheritString( intf, "flix-tmdb-base-url" );
    const bool custom = base != nullptr && base[0] != '\0';
    free( base );
    const QString path = QDir::fromNativeSeparators( qfu( dir ) ) + QStringLiteral("/flix-meta/")
                       + ( custom ? QStringLiteral("test") : QStringLiteral("tmdb") );
    free( dir );
    return path;
}

static QString metaFileUrl( const QString &directory, const QString &relative )
{
    if( relative.isEmpty() || relative.contains( QStringLiteral("..") ) )
        return QString();
    const QString path = directory + QLatin1Char('/') + relative;
    return QFile::exists( path ) ? QUrl::fromLocalFile( path ).toString() : QString();
}

static QVariantMap metaRecordToMap( const QJsonObject &o, const QString &directory )
{
    QVariantMap m;
    m.insert( QStringLiteral("found"), o.value( QStringLiteral("found") ).toBool() );
    m.insert( QStringLiteral("title"), o.value( QStringLiteral("title") ).toString() );
    m.insert( QStringLiteral("year"), o.value( QStringLiteral("year") ).toInt() );
    m.insert( QStringLiteral("overview"), o.value( QStringLiteral("overview") ).toString() );
    m.insert( QStringLiteral("tagline"), o.value( QStringLiteral("tagline") ).toString() );
    m.insert( QStringLiteral("runtime"), o.value( QStringLiteral("runtime") ).toInt() );
    m.insert( QStringLiteral("rating"), o.value( QStringLiteral("rating") ).toDouble() );
    m.insert( QStringLiteral("certification"), o.value( QStringLiteral("certification") ).toString() );
    m.insert( QStringLiteral("imdbId"), o.value( QStringLiteral("imdb_id") ).toString() );
    m.insert( QStringLiteral("mediaType"), o.value( QStringLiteral("media_type") ).toString() );
    m.insert( QStringLiteral("tmdbId"), o.value( QStringLiteral("tmdb_id") ).toInt() );
    m.insert( QStringLiteral("genres"), o.value( QStringLiteral("genres") ).toArray().toVariantList() );
    m.insert( QStringLiteral("poster"), metaFileUrl( directory, o.value( QStringLiteral("poster") ).toString() ) );
    m.insert( QStringLiteral("backdrop"), metaFileUrl( directory, o.value( QStringLiteral("backdrop") ).toString() ) );
    return m;
}

QUrl MainCtx::pickFolder(const QString &title) const
{
    QUrl url = QFileDialog::getExistingDirectoryUrl( nullptr, title, QUrl() );
    if( !url.isValid() || url.isEmpty() )
        return url;

    // flix: the medialibrary wants a folder url that ends in a separator, which is not
    // what the file dialog hands back. Without it the library refuses the folder and
    // does so silently, so "Add movie folder" looked like it did nothing at all.
    if( !url.path().endsWith( QLatin1Char('/') ) )
        url.setPath( url.path() + QLatin1Char('/') );
    return url;
}

QString MainCtx::torrentHelper() const
{
#ifdef _WIN32
    const QString name = QStringLiteral("flixtorrent.exe");
#else
    const QString name = QStringLiteral("flixtorrent");
#endif
    return QCoreApplication::applicationDirPath() + QStringLiteral("/flix/") + name;
}

QString MainCtx::torrentDir() const
{
    char *dir = config_GetUserDir( VLC_USERDATA_DIR );
    if( dir == nullptr )
        return QString();
    const QString path = QDir::fromNativeSeparators( qfu( dir ) ) + QStringLiteral("/flix-torrents");
    free( dir );
    return path;
}

QString MainCtx::clipboardMagnet() const
{
    static const QRegularExpression magnetRe( QStringLiteral("^magnet:\\?xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(&.*)?$") );
    const QString text = QGuiApplication::clipboard()->text().trimmed();
    return magnetRe.match( text ).hasMatch() ? text : QString();
}

QString MainCtx::pickTorrentFile(const QString &title) const
{
    return QFileDialog::getOpenFileName( nullptr, title, QString(), QStringLiteral("Torrent files (*.torrent)") );
}

void MainCtx::torrentFiles(const QVariantMap &source)
{
    static const QRegularExpression magnetRe( QStringLiteral("^magnet:\\?xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(&.*)?$") );
    const QString magnet = source.value( QStringLiteral("magnet") ).toString().trimmed();
    const QString torrentFile = source.value( QStringLiteral("torrentFile") ).toString();
    const bool valid = torrentFile.isEmpty() ? magnetRe.match( magnet ).hasMatch()
                                             : ( torrentFile.endsWith( QLatin1String(".torrent"), Qt::CaseInsensitive )
                                                 && QFileInfo::exists( torrentFile ) );
    if( !valid )
    {
        emit torrentFilesReady( QString(), {}, tr("That is not a magnet link or a .torrent file.") );
        return;
    }
    if( !torrentAvailable() )
    {
        emit torrentFilesReady( QString(), {}, tr("The torrent helper is not installed (run flix/build-torrent.ps1).") );
        return;
    }
    if( m_filesProc )
    {
        m_filesProc->disconnect( this );
        m_filesProc->kill();
        m_filesProc->deleteLater();
    }
    m_filesProc = new QProcess( this );
    QProcess *proc = m_filesProc;
    connect( proc, &QProcess::finished, this, [this, proc]( int code, QProcess::ExitStatus ) {
        const QByteArray out = proc->readAllStandardOutput();
        if( m_filesProc == proc )
            m_filesProc = nullptr;
        proc->deleteLater();
        const QJsonObject o = QJsonDocument::fromJson( out ).object();
        if( code != 0 || o.contains( QStringLiteral("error") ) || o.isEmpty() )
        {
            emit torrentFilesReady( QString(), {}, o.value( QStringLiteral("error") ).toString( tr("Could not read the torrent.") ) );
            return;
        }
        emit torrentFilesReady( o.value( QStringLiteral("name") ).toString(),
                                o.value( QStringLiteral("files") ).toArray().toVariantList(), QString() );
    } );
    connect( proc, &QProcess::errorOccurred, this, [this, proc]( QProcess::ProcessError e ) {
        if( e != QProcess::FailedToStart )
            return;
        if( m_filesProc == proc )
            m_filesProc = nullptr;
        proc->deleteLater();
        emit torrentFilesReady( QString(), {}, tr("Could not start the torrent helper.") );
    } );
    QStringList args { QStringLiteral("files"),
                       torrentFile.isEmpty() ? QStringLiteral("--magnet") : QStringLiteral("--torrent-file"),
                       torrentFile.isEmpty() ? magnet : torrentFile,
                       QStringLiteral("--data-dir"),
                       torrentDir() + QStringLiteral("/files-") + QString::number( QDateTime::currentSecsSinceEpoch() ),
                       // the metadata fetched here is saved for the stream that follows
                       QStringLiteral("--cache-root"), torrentDir() + QStringLiteral("/data") };
    args << trackerArgs();
    proc->start( torrentHelper(), args );
}

// --- web player -----------------------------------------------------------------------

static const char *const defaultProviders = R"JSON([
  {"name": "VidStuck",    "host": "vidstuck.xyz",      "movie": "https://vidstuck.xyz/embed/movie/{tmdb}", "tv": "https://vidstuck.xyz/embed/tv/{tmdb}/{season}/{episode}", "start": "progress"},
  {"name": "VidLink",     "host": "vidlink.pro",       "movie": "https://vidlink.pro/movie/{tmdb}",       "tv": "https://vidlink.pro/tv/{tmdb}/{season}/{episode}", "start": "startAt"},
  {"name": "VixSrc",      "host": "vixsrc.to",         "movie": "https://vixsrc.to/movie/{tmdb}",         "tv": "https://vixsrc.to/tv/{tmdb}/{season}/{episode}"},
  {"name": "VidFast",     "host": "vidfast.vc",        "movie": "https://vidfast.vc/movie/{tmdb}",        "tv": "https://vidfast.vc/tv/{tmdb}/{season}/{episode}", "start": "startAt"},
  {"name": "VidZee",      "host": "vidzee.wtf",        "movie": "https://vidzee.wtf/movie/{tmdb}",        "tv": "https://vidzee.wtf/tv/{tmdb}/{season}/{episode}"},
  {"name": "VidNest",     "host": "vidnest.fun",       "movie": "https://vidnest.fun/movie/{tmdb}",       "tv": "https://vidnest.fun/tv/{tmdb}/{season}/{episode}"},
  {"name": "CineSrc",     "host": "cinesrc.st",        "movie": "https://cinesrc.st/embed/movie/{tmdb}",  "tv": "https://cinesrc.st/embed/tv/{tmdb}?s={season}&e={episode}"},
  {"name": "Atlantic",    "host": "atlantic.st",       "movie": "https://atlantic.st/movie/{tmdb}",       "tv": "https://atlantic.st/tv/{tmdb}/{season}/{episode}"},
  {"name": "VidRift",     "host": "vidrift.net",       "movie": "https://vidrift.net/?tmdb={tmdb}",        "tv": "https://vidrift.net/?tmdb={tmdb}&s={season}&e={episode}"},
  {"name": "Vidy",        "host": "www.vidy.st",       "movie": "https://www.vidy.st/movie/{tmdb}",       "tv": "https://www.vidy.st/tv/{tmdb}/{season}/{episode}"},
  {"name": "SuperEmbed",  "host": "superembed.stream", "movie": "https://superembed.stream/?tmdb={tmdb}",  "tv": "https://superembed.stream/?tmdb={tmdb}&s={season}&e={episode}"},
  {"name": "PrimeWire",   "host": "primewire.mov",     "movie": "https://primewire.mov/movie/{tmdb}",     "tv": "https://primewire.mov/tv/{tmdb}/{season}/{episode}"}
])JSON";

QVariantList MainCtx::webProviders()
{
    // user-editable: written once, then read every time so URL patterns can be corrected
    const QString path = torrentDir() + QStringLiteral("/../flix-providers.json");
    if( !QFileInfo::exists( path ) )
    {
        QFile out( path );
        if( out.open( QIODevice::WriteOnly ) )
            out.write( defaultProviders );
    }
    QFile file( path );
    QByteArray raw = defaultProviders;
    if( file.open( QIODevice::ReadOnly ) )
        raw = file.readAll();
    QJsonArray list = QJsonDocument::fromJson( raw ).array();
    if( list.isEmpty() )
        list = QJsonDocument::fromJson( defaultProviders ).array();
    QVariantList result;
    for( const QJsonValue &v : std::as_const( list ) )
    {
        const QJsonObject o = v.toObject();
        // only https pages on the provider's own host are ever opened
        const QString host = o.value( QStringLiteral("host") ).toString();
        if( host.isEmpty() )
            continue;
        QVariantMap m = o.toVariantMap();
        result.append( m );
    }
    // the preferred provider (VidStuck unless changed) goes first, whatever order the file has
    const QString preferred = flixPref( QStringLiteral("web/default"), QStringLiteral("VidStuck") ).toString();
    for( int i = 1; i < result.size(); ++i )
        if( result.at( i ).toMap().value( QStringLiteral("name") ).toString() == preferred )
        {
            result.move( i, 0 );
            break;
        }
    return result;
}

bool MainCtx::webPlayerAvailable() const
{
#ifdef _WIN32
    return QFileInfo::exists( QCoreApplication::applicationDirPath() + QStringLiteral("/flix/flixweb.exe") );
#else
    return false;
#endif
}

void MainCtx::openWebPlayer(const QUrl &url, const QString &title, bool frame, const QVariantMap &info)
{
    if( url.scheme() != QLatin1String("https") || url.host().isEmpty() )
        return;
    if( !webPlayerAvailable() )
    {
        // no WebView2 helper: the default browser does the job
        QDesktopServices::openUrl( url );
        return;
    }
    if( m_webProc )
    {
        m_webProc->disconnect( this );
        m_webProc->kill();
        m_webProc->deleteLater();
    }
    m_webBuffer.clear();
    m_webProc = new QProcess( this );
    QProcess *proc = m_webProc;
    const QString key = info.value( QStringLiteral("key") ).toString();
    connect( proc, &QProcess::readyReadStandardOutput, this, [this, proc, info, key]() {
        m_webBuffer += proc->readAllStandardOutput();
        int nl;
        while( ( nl = m_webBuffer.indexOf( '\n' ) ) >= 0 )
        {
            const QJsonObject o = QJsonDocument::fromJson( m_webBuffer.left( nl ) ).object();
            m_webBuffer.remove( 0, nl + 1 );
            if( key.isEmpty() || o.value( QStringLiteral("event") ).toString() != QLatin1String("progress") )
                continue;
            const double seconds = o.value( QStringLiteral("seconds") ).toDouble();
            const double length = o.value( QStringLiteral("duration") ).toDouble();
            QVariantMap all = readResume();
            QVariantMap entry = info;
            entry.insert( QStringLiteral("kind"), QStringLiteral("web") );
            entry.insert( QStringLiteral("seconds"), int( seconds ) );
            entry.insert( QStringLiteral("length"), int( length ) );
            entry.insert( QStringLiteral("fraction"), length > 0 ? seconds / length : 0.0 );
            entry.insert( QStringLiteral("updated"), QDateTime::currentSecsSinceEpoch() );
            // finished (>95 %) or barely started (<30 s): not worth continuing
            if( length > 0 && seconds / length > 0.95 )
                all.remove( key );
            else if( seconds >= 20 )
                all.insert( key, entry );
            writeResume( all );
            emit resumeChanged();
        }
    } );
    connect( proc, &QProcess::finished, this, [this, proc]( int code, QProcess::ExitStatus ) {
        const QByteArray err = proc->readAllStandardError().trimmed();
        msg_Dbg( p_intf, "flixweb ended: code %d %s", code, err.constData() );
        if( m_webProc == proc )
            m_webProc = nullptr;
        // WebView2 missing or failed to start: fall back to the browser
        if( code == 3 )
            QDesktopServices::openUrl( proc->property( "flixUrl" ).toUrl() );
        proc->deleteLater();
    } );
    proc->setProperty( "flixUrl", url );
    QStringList args { QStringLiteral("--url"), url.toString( QUrl::FullyEncoded ),
                       QStringLiteral("--title"), title,
                       QStringLiteral("--data-dir"), torrentDir() + QStringLiteral("/../flix-web"),
                       QStringLiteral("--parent-pid"), QString::number( QCoreApplication::applicationPid() ) };
    if( frame && !key.isEmpty() )
        args << QStringLiteral("--frame");
    if( info.value( QStringLiteral("start") ).toInt() > 0 )
        args << QStringLiteral("--start") << QString::number( info.value( QStringLiteral("start") ).toInt() );
    proc->start( QCoreApplication::applicationDirPath() + QStringLiteral("/flix/flixweb.exe"), args );
}

// --- continue watching store (<userdata>/flix-resume.json) -----------------------------------

QString MainCtx::userFile(const QString &name) const
{
    char *dir = config_GetUserDir( VLC_USERDATA_DIR );
    if( dir == nullptr )
        return QString();
    const QString path = QDir::fromNativeSeparators( qfu( dir ) ) + QLatin1Char('/') + name;
    free( dir );
    return path;
}

QVariantMap MainCtx::readResume() const
{
    QFile f( userFile( QStringLiteral("flix-resume.json") ) );
    if( !f.open( QIODevice::ReadOnly ) )
        return {};
    return QJsonDocument::fromJson( f.readAll() ).object().toVariantMap();
}

void MainCtx::writeResume(const QVariantMap &all) const
{
    // temp file + rename: a crash cannot leave a half written store
    const QString path = userFile( QStringLiteral("flix-resume.json") );
    QFile f( path + QStringLiteral(".tmp") );
    if( !f.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
        return;
    f.write( QJsonDocument( QJsonObject::fromVariantMap( all ) ).toJson( QJsonDocument::Compact ) );
    f.close();
    QFile::remove( path );
    f.rename( path );
}

int MainCtx::webResumeSeconds(const QString &key) const
{
    return readResume().value( key ).toMap().value( QStringLiteral("seconds") ).toInt();
}

QVariantList MainCtx::resumeList() const
{
    const QVariantMap all = readResume();
    QVariantList list;
    for( auto it = all.begin(); it != all.end(); ++it )
    {
        QVariantMap e = it.value().toMap();
        e.insert( QStringLiteral("key"), it.key() );
        list.append( e );
    }
    std::sort( list.begin(), list.end(), []( const QVariant &a, const QVariant &b ) {
        return a.toMap().value( QStringLiteral("updated") ).toLongLong()
             > b.toMap().value( QStringLiteral("updated") ).toLongLong();
    } );
    return list;
}

void MainCtx::removeResume(const QString &key)
{
    QVariantMap all = readResume();
    if( all.remove( key ) )
    {
        writeResume( all );
        emit resumeChanged();
    }
}

double MainCtx::torrentResume() const
{
    const QString key = m_torrentSession.value( QStringLiteral("resumeKey") ).toString();
    if( key.isEmpty() || m_torrentSession.value( QStringLiteral("fromStart") ).toBool() )
        return 0.0;
    const double f = readResume().value( key ).toMap().value( QStringLiteral("fraction") ).toDouble();
    return ( f > 0.03 && f < 0.95 ) ? f : 0.0;
}

void MainCtx::saveTorrentResume(double fraction, int seconds, int length)
{
    const QString key = m_torrentSession.value( QStringLiteral("resumeKey") ).toString();
    if( key.isEmpty() || length <= 0 )
        return;
    QVariantMap all = readResume();
    if( fraction > 0.95 )
        all.remove( key );
    else if( fraction > 0.03 )
    {
        QVariantMap e = m_torrentSession.value( QStringLiteral("meta") ).toMap();
        e.insert( QStringLiteral("kind"), QStringLiteral("torrent") );
        e.insert( QStringLiteral("title"), m_torrentSession.value( QStringLiteral("title") ) );
        e.insert( QStringLiteral("magnet"), m_torrentSession.value( QStringLiteral("magnet") ) );
        e.insert( QStringLiteral("torrentFile"), m_torrentSession.value( QStringLiteral("torrentFile") ) );
        e.insert( QStringLiteral("fileIdx"), m_torrentSession.value( QStringLiteral("fileIdx"), -1 ) );
        e.insert( QStringLiteral("fraction"), fraction );
        e.insert( QStringLiteral("seconds"), seconds );
        e.insert( QStringLiteral("length"), length );
        e.insert( QStringLiteral("updated"), QDateTime::currentSecsSinceEpoch() );
        all.insert( key, e );
    }
    else
        return;
    writeResume( all );
    emit resumeChanged();
}

static QString localResumeKey( const QString &mrl )
{
    // the library writes an address encoded, the player hands over a decoded one: same key for both
    const QByteArray normal = QUrl( mrl ).toEncoded();
    return QStringLiteral("f:") + QString::fromLatin1(
        QCryptographicHash::hash( normal.isEmpty() ? mrl.toUtf8() : normal, QCryptographicHash::Sha1 ).toHex().left( 20 ) );
}

void MainCtx::importResume(const QString &mrl, const QString &name, double fraction, qint64 updated)
{
    if( mrl.isEmpty() || mrl.startsWith( QStringLiteral("http://127.0.0.1:") ) || fraction <= 0.03 || fraction >= 0.95 )
        return;
    const QString key = localResumeKey( mrl );
    QVariantMap all = readResume();
    if( all.contains( key ) )
        return;
    const QVariantMap info = releaseInfo( name );
    const QVariantMap m = meta( name );
    QVariantMap e;
    e.insert( QStringLiteral("kind"), QStringLiteral("local") );
    e.insert( QStringLiteral("mrl"), mrl );
    const QString found = m.value( QStringLiteral("found") ).toBool() ? m.value( QStringLiteral("title") ).toString() : QString();
    e.insert( QStringLiteral("title"), !found.isEmpty() ? found : info.value( QStringLiteral("title") ).toString() );
    e.insert( QStringLiteral("poster"), m.value( QStringLiteral("poster") ) );
    e.insert( QStringLiteral("mediaType"), info.value( QStringLiteral("isEpisode") ).toBool() ? QStringLiteral("tv") : QStringLiteral("movie") );
    e.insert( QStringLiteral("season"), info.value( QStringLiteral("season") ) );
    e.insert( QStringLiteral("episode"), info.value( QStringLiteral("episode") ) );
    e.insert( QStringLiteral("fraction"), fraction );
    e.insert( QStringLiteral("seconds"), 0 );
    e.insert( QStringLiteral("length"), 0 );
    e.insert( QStringLiteral("updated"), updated );
    all.insert( key, e );
    writeResume( all );
    emit resumeChanged();
}

void MainCtx::clearResume()
{
    writeResume( QVariantMap() );
    emit resumeChanged();
}

void MainCtx::saveLocalResume(const QString &mrl, const QString &name, double fraction, int seconds, int length)
{
    if( mrl.isEmpty() || length <= 0 )
        return;
    const QString key = localResumeKey( mrl );
    QVariantMap all = readResume();
    if( fraction > 0.95 )
    {
        if( !all.remove( key ) )
            return;
    }
    else if( fraction > 0.03 )
    {
        const QVariantMap info = releaseInfo( name );
        const QVariantMap m = meta( name );
        QVariantMap e;
        e.insert( QStringLiteral("kind"), QStringLiteral("local") );
        e.insert( QStringLiteral("mrl"), mrl );
        const QString found = m.value( QStringLiteral("found") ).toBool() ? m.value( QStringLiteral("title") ).toString() : QString();
        e.insert( QStringLiteral("title"), !found.isEmpty() ? found : info.value( QStringLiteral("title") ).toString() );
        e.insert( QStringLiteral("poster"), m.value( QStringLiteral("poster") ) );
        e.insert( QStringLiteral("mediaType"), info.value( QStringLiteral("isEpisode") ).toBool() ? QStringLiteral("tv") : QStringLiteral("movie") );
        e.insert( QStringLiteral("season"), info.value( QStringLiteral("season") ) );
        e.insert( QStringLiteral("episode"), info.value( QStringLiteral("episode") ) );
        e.insert( QStringLiteral("fraction"), fraction );
        e.insert( QStringLiteral("seconds"), seconds );
        e.insert( QStringLiteral("length"), length );
        e.insert( QStringLiteral("updated"), QDateTime::currentSecsSinceEpoch() );
        all.insert( key, e );
    }
    else
        return;
    writeResume( all );
    emit resumeChanged();
}

// --- VLCFlix settings -----------------------------------------------------------------------

static bool flixOptionAllowed( const QString &name )
{
    static const QSet<QString> allowed {
        QStringLiteral("flixsubs-api-key"), QStringLiteral("flixsubs-user"), QStringLiteral("flixsubs-password"),
        QStringLiteral("flixsubs-languages"), QStringLiteral("flixsubs-auto"), QStringLiteral("flixsubs-ask"),
        QStringLiteral("flix-tmdb-token"), QStringLiteral("flix-meta-language"), QStringLiteral("flix-top10-target"),
        QStringLiteral("flix-update-check"),
    };
    return allowed.contains( name );
}

QVariant MainCtx::vlcOption(const QString &name) const
{
    if( !flixOptionAllowed( name ) )
        return {};
    const QByteArray n = name.toUtf8();
    switch( config_GetType( n.constData() ) )
    {
        case VLC_VAR_STRING:
        {
            char *v = var_InheritString( p_intf, n.constData() );
            const QString r = v ? qfu( v ) : QString();
            free( v );
            return r;
        }
        case VLC_VAR_BOOL:
            return bool( var_InheritBool( p_intf, n.constData() ) );
        case VLC_VAR_INTEGER:
            return qlonglong( var_InheritInteger( p_intf, n.constData() ) );
        default:
            return {};
    }
}

bool MainCtx::hasVlcOption(const QString &name) const
{
    const QVariant v = vlcOption( name );
    return v.isValid() && !v.toString().isEmpty();
}

bool MainCtx::setVlcOption(const QString &name, const QVariant &value)
{
    if( !flixOptionAllowed( name ) )
        return false;
    const QByteArray n = name.toUtf8();
    switch( config_GetType( n.constData() ) )
    {
        case VLC_VAR_STRING:
        {
            // a password is kept exactly as typed; everything else loses stray spaces
            const QString text = name == QLatin1String("flixsubs-password") ? value.toString()
                                                                            : value.toString().trimmed();
            config_PutPsz( n.constData(), text.toUtf8().constData() );
            break;
        }
        case VLC_VAR_BOOL:
            config_PutInt( n.constData(), value.toBool() ? 1 : 0 );
            break;
        case VLC_VAR_INTEGER:
            config_PutInt( n.constData(), value.toLongLong() );
            break;
        default:
            return false;
    }
    config_SaveConfigFile( p_intf );
    return true;
}

void MainCtx::testAccount(const QVariantMap &request)
{
    // handed to the Lua service in this process; nothing is logged or written to disk here
    var_SetString( vlc_object_instance(p_intf), "flix-account-request",
                   QJsonDocument( QJsonObject::fromVariantMap( request ) ).toJson( QJsonDocument::Compact ).constData() );
}

void MainCtx::emitAccountResult(const QString &json)
{
    const QJsonObject o = QJsonDocument::fromJson( json.toUtf8() ).object();
    emit accountTestResult( o.value( QStringLiteral("kind") ).toString(), o.value( QStringLiteral("ok") ).toBool(),
                            o.value( QStringLiteral("message") ).toString() );
}

QString MainCtx::providersFile() const
{
    return QDir::toNativeSeparators( QDir::cleanPath( torrentDir() + QStringLiteral("/../flix-providers.json") ) );
}

void MainCtx::resetWebProviders()
{
    QFile out( torrentDir() + QStringLiteral("/../flix-providers.json") );
    if( out.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
        out.write( defaultProviders );
}

// --- trackers -------------------------------------------------------------------------------

QString MainCtx::userTrackers() const
{
    QFile f( userFile( QStringLiteral("flix-trackers.txt") ) );
    return f.open( QIODevice::ReadOnly ) ? QString::fromUtf8( f.readAll() ) : QString();
}

QVariantMap MainCtx::setUserTrackers(const QString &text)
{
    static const QRegularExpression trackerRe( QStringLiteral("^(udp|http|https|wss?)://[^\\s/]+(:\\d{1,5})?(/\\S*)?$"),
                                               QRegularExpression::CaseInsensitiveOption );
    QStringList good, bad;
    for( const QString &raw : text.split( QLatin1Char('\n') ) )
    {
        const QString line = raw.trimmed();
        if( line.isEmpty() )
            continue;
        if( line.startsWith( QLatin1Char('#') ) || trackerRe.match( line ).hasMatch() )
            good << line;
        else
            bad << line;
    }
    bool saved = false;
    QFile f( userFile( QStringLiteral("flix-trackers.txt") ) );
    if( bad.isEmpty() && f.open( QIODevice::WriteOnly | QIODevice::Truncate ) )
    {
        f.write( good.join( QLatin1Char('\n') ).toUtf8() + "\n" );
        saved = true;
    }
    QVariantMap r;
    r.insert( QStringLiteral("saved"), saved );
    r.insert( QStringLiteral("invalid"), bad );
    return r;
}

// per-item options for a torrent stream.
//
// The stock http access gives the decoders one second of runway (network-caching). A
// swarm takes longer than that to hand over the next piece, and an audio decoder that
// runs out of buffer does not wait: it drops and resynchronises, which is the crackle
// and the doubling. Four seconds covers an ordinary piece fetch with room to spare.
// 0 in the settings leaves the default alone.
QStringList MainCtx::torrentStreamOptions(const QString &title) const
{
    QStringList options;
    if( !title.isEmpty() )
        options << QStringLiteral("meta-title=") + title;
    const int caching = flixPref( QStringLiteral("torrent/networkCaching"), 4000 ).toInt();
    if( caching > 0 )
        options << QStringLiteral("network-caching=%1").arg( caching );
    return options;
}

// flix: start the helper's stream under the film's own name.
//
// Through MediaLib::addAndPlay(url) the playlist item was *named* after the url, and the
// "meta-title" option above does not rescue it: the input only reads it for an item that
// has not been preparsed, and the playlist preparses what it is given. So the window title
// and the player's title bar fell back to the name, and cleanTitle() turned its dots into
// spaces: "http://127 0 0 1 ...".
//
// The title is set on the item at playlist priority, the way an m3u entry's title is.
// That keeps it above whatever tag the file itself carries, which for a torrent is often
// the release name or the address of the site it came from.
int MainCtx::playTorrentStream(const QString &url, const QString &title)
{
    const QString name = title.trimmed();
    QStringList options = torrentStreamOptions( name );

    // Continuing: open straight at the saved time, five seconds early as streaming
    // services do. This used to play from 0 and seek from QML once playback had begun,
    // then seek again four seconds later when the position had not moved yet (it cannot,
    // while the first seek is still buffering). Every one of those seeks dropped a
    // connection and opened another. flix-resume-time is a seek queued before the input
    // starts (vlc_player_input_New), so the demuxer goes to the right place through the
    // file's own index before anything is played.
    //
    // It is not start-time, which this used before: start-time makes the saved time the
    // seek bar's zero. The bar read 0:00 at the resume point against only the time left,
    // "Start over" went back to the resume point, and the position saved for the next
    // resume was counted from it, so every continue landed earlier than the last.
    int startAt = 0;
    if( torrentResume() > 0.0 )
    {
        const QString key = m_torrentSession.value( QStringLiteral("resumeKey") ).toString();
        const QVariantMap e = readResume().value( key ).toMap();
        double seconds = e.value( QStringLiteral("seconds") ).toDouble();
        if( seconds <= 0 )
            seconds = e.value( QStringLiteral("fraction") ).toDouble() * e.value( QStringLiteral("length") ).toDouble();
        startAt = qMax( 0, int( seconds ) - 5 );
        if( startAt > 0 )
            options << QStringLiteral("flix-resume-time=%1").arg( startAt );
    }

    vlc::playlist::Media media{ url, name.isEmpty() ? url : name, options };
    if( !name.isEmpty() )
    {
        input_item_t *item = media.raw();
        vlc_mutex_lock( &item->lock );
        if( item->p_meta == nullptr )
            item->p_meta = vlc_meta_New();
        if( item->p_meta != nullptr )
            vlc_meta_SetWithPriority( item->p_meta, vlc_meta_Title, qtu( name ),
                                      VLC_META_PRIORITY_PLAYLIST );
        vlc_mutex_unlock( &item->lock );
    }
    THEMPL->append( QVector<vlc::playlist::Media>{ media }, true );
    return startAt;
}

// flix: the storage page used to refuse to clear the torrent data whenever the helper
// process object still existed. The helper deliberately waits on this very process, so
// that said nothing about whether anything was reading. Ask instead whether a stream
// is really playing: a helper with no input behind it is not holding the files.
bool MainCtx::torrentActive() const
{
    return m_torrentActive && m_streamProc != nullptr;
}

QStringList MainCtx::trackerArgs() const
{
    const QString path = userFile( QStringLiteral("flix-trackers.txt") );
    return QFileInfo::exists( path ) ? QStringList { QStringLiteral("--trackers-file"), path } : QStringList();
}

// speed caps in bytes/s; 0 (or unset) means unlimited, and then the flag is left out
QStringList MainCtx::rateArgs() const
{
    QStringList args;
    const qint64 down = flixPref( QStringLiteral("torrent/rateDown"), 0 ).toLongLong();
    if( down > 0 )
        args << QStringLiteral("--rate-limit") << QString::number( down );
    const qint64 up = flixPref( QStringLiteral("torrent/rateUp"), 0 ).toLongLong();
    if( up > 0 )
        args << QStringLiteral("--upload-rate-limit") << QString::number( up );
    return args;
}

// fetch only what the player is about to need ("stream"), or the whole file
QStringList MainCtx::streamArgs() const
{
    const bool bStream = flixPref( QStringLiteral("torrent/streamOnly"), true ).toBool();
    const qint64 window = flixPref( QStringLiteral("torrent/streamWindow"), 32 * 1024 * 1024 ).toLongLong();
    return { bStream ? QStringLiteral("--stream-only=true")
                     : QStringLiteral("--stream-only=false"),
             QStringLiteral("--stream-window"), QString::number( window ) };
}

// --- storage --------------------------------------------------------------------------------

namespace {
struct StorageKind { const char *kind; const char *label; };
const StorageKind storageKinds[] = {
    { "torrentData",  QT_TRANSLATE_NOOP("MainCtx", "Torrent downloads (partial videos)") },
    { "torrentCache", QT_TRANSLATE_NOOP("MainCtx", "Torrent source lists") },
    { "meta",         QT_TRANSLATE_NOOP("MainCtx", "Posters and movie information (TMDB)") },
    { "subtitles",    QT_TRANSLATE_NOOP("MainCtx", "Downloaded subtitles") },
    { "web",          QT_TRANSLATE_NOOP("MainCtx", "Web player cookies and cache") },
    { "resume",       QT_TRANSLATE_NOOP("MainCtx", "Continue watching history") },
};

void dirSize( const QString &path, qint64 &bytes, int &files )
{
    QDirIterator it( path, QDir::Files | QDir::Hidden, QDirIterator::Subdirectories );
    while( it.hasNext() )
    {
        it.next();
        bytes += it.fileInfo().size();
        ++files;
    }
}
}

QVariantList MainCtx::storageInfo() const
{
    QVariantList list;
    // data: the kept torrents (one folder each); data-* and files-*: per-session leftovers
    const QStringList dataFilters { QStringLiteral("data"), QStringLiteral("data-*"), QStringLiteral("files-*") };
    for( const StorageKind &k : storageKinds )
    {
        qint64 bytes = 0;
        int files = 0;
        const QString kind = QString::fromLatin1( k.kind );
        if( kind == QLatin1String("torrentData") )
        {
            const QDir base( torrentDir() );
            for( const QString &d : base.entryList( dataFilters, QDir::Dirs | QDir::NoDotAndDotDot ) )
                dirSize( base.filePath( d ), bytes, files );
        }
        else if( kind == QLatin1String("torrentCache") )
            dirSize( torrentDir() + QStringLiteral("/cache"), bytes, files );
        else if( kind == QLatin1String("meta") )
            dirSize( userFile( QStringLiteral("flix-meta") ), bytes, files );
        else if( kind == QLatin1String("subtitles") )
            dirSize( userFile( QStringLiteral("subtitles") ), bytes, files );
        else if( kind == QLatin1String("web") )
            dirSize( userFile( QStringLiteral("flix-web") ), bytes, files );
        else
        {
            const QFileInfo fi( userFile( QStringLiteral("flix-resume.json") ) );
            if( fi.exists() )
            {
                bytes = fi.size();
                files = 1;
            }
        }
        QVariantMap m;
        m.insert( QStringLiteral("kind"), kind );
        m.insert( QStringLiteral("label"), QCoreApplication::translate( "MainCtx", k.label ) );
        m.insert( QStringLiteral("bytes"), bytes );
        m.insert( QStringLiteral("files"), files );
        list.append( m );
    }
    return list;
}

bool MainCtx::clearStorage(const QString &kind)
{
    // fixed folders under the user data folder only: nothing here comes from a path given by QML
    if( kind == QLatin1String("torrentData") )
    {
        // A stream that is really playing holds these files. One that is not does not,
        // and refusing there is what left the page saying "in use by the current
        // stream" for a stream that had not run in hours: the check used to be "does
        // the helper process exist", and the helper watches this very process and
        // stays alive until we stop it. So an idle helper is simply stopped here.
        if( torrentActive() )
            return false;
        stopTorrent();
        const QDir base( torrentDir() );
        for( const QString &d : base.entryList( { QStringLiteral("data"), QStringLiteral("data-*"), QStringLiteral("files-*") }, QDir::Dirs | QDir::NoDotAndDotDot ) )
            QDir( base.filePath( d ) ).removeRecursively();
        return true;
    }
    if( kind == QLatin1String("torrentCache") )
        return QDir( torrentDir() + QStringLiteral("/cache") ).removeRecursively();
    if( kind == QLatin1String("meta") )
    {
        const bool ok = QDir( userFile( QStringLiteral("flix-meta") ) ).removeRecursively();
        emit metaUpdated( QStringLiteral("top10") );
        return ok;
    }
    if( kind == QLatin1String("subtitles") )
        return QDir( userFile( QStringLiteral("subtitles") ) ).removeRecursively();
    if( kind == QLatin1String("web") )
    {
        // the web player is a separate window, so the helper existing is exactly the
        // right test here - unlike the torrent, nothing plays it inside this process
        if( m_webProc )
            return false;
        return QDir( userFile( QStringLiteral("flix-web") ) ).removeRecursively();
    }
    if( kind == QLatin1String("resume") )
    {
        QFile::remove( userFile( QStringLiteral("flix-resume.json") ) );
        emit resumeChanged();
        return true;
    }
    return false;
}

bool MainCtx::torrentAvailable() const
{
    return QFileInfo::exists( torrentHelper() );
}

void MainCtx::torrentSources(const QString &imdbId, int season, int episode)
{
    static const QRegularExpression imdbRe( QStringLiteral("^tt\\d{5,10}$") );
    if( !imdbRe.match( imdbId ).hasMatch() )
    {
        emit torrentSourcesReady( {}, tr("This title has no IMDb id yet.") );
        return;
    }
    if( !torrentAvailable() )
    {
        emit torrentSourcesReady( {}, tr("The torrent helper is not installed (run flix/build-torrent.ps1).") );
        return;
    }
    if( m_sourcesProc )
    {
        // a newer request replaces the running one
        m_sourcesProc->disconnect( this );
        m_sourcesProc->kill();
        m_sourcesProc->deleteLater();
    }
    m_sourcesProc = new QProcess( this );
    QProcess *proc = m_sourcesProc;
    QStringList args { QStringLiteral("sources"), QStringLiteral("--imdb"), imdbId,
                       QStringLiteral("--cache"), torrentDir() + QStringLiteral("/cache") };
    if( season > 0 && episode > 0 )
        args << QStringLiteral("--season") << QString::number( season )
             << QStringLiteral("--episode") << QString::number( episode );

    connect( proc, &QProcess::finished, this, [this, proc]( int code, QProcess::ExitStatus ) {
        const QByteArray out = proc->readAllStandardOutput();
        if( m_sourcesProc == proc )
            m_sourcesProc = nullptr;
        proc->deleteLater();
        const QJsonObject o = QJsonDocument::fromJson( out ).object();
        if( code != 0 || o.isEmpty() )
        {
            emit torrentSourcesReady( {}, o.value( QStringLiteral("error") ).toString( tr("Could not load sources.") ) );
            return;
        }
        emit torrentSourcesReady( o.value( QStringLiteral("sources") ).toArray().toVariantList(), QString() );
    } );
    connect( proc, &QProcess::errorOccurred, this, [this, proc]( QProcess::ProcessError e ) {
        if( e != QProcess::FailedToStart )
            return;
        if( m_sourcesProc == proc )
            m_sourcesProc = nullptr;
        proc->deleteLater();
        emit torrentSourcesReady( {}, tr("Could not start the torrent helper.") );
    } );
    args << trackerArgs();
    proc->start( torrentHelper(), args );
}

void MainCtx::stopTorrent()
{
    if( !m_streamProc && !m_torrentActive && m_torrentDataDir.isEmpty() )
        return;
    msg_Dbg( p_intf, "flixtorrent: stopping the stream helper" );
    if( !m_torrentStats.isEmpty() )
    {
        m_torrentStats.clear();
        emit torrentStatsChanged();
    }
    var_SetString( vlc_object_instance(p_intf), "flix-stream-info", "" );

    QProcess *proc = m_streamProc;
    m_streamProc = nullptr;
    setTorrentActive( false );
    if( proc )
    {
        proc->disconnect( this );
        // closing stdin tells the helper to quit and clean up; kill it if it does not
        proc->closeWriteChannel();
        proc->terminate();
        if( !proc->waitForFinished( 800 ) )
        {
            proc->kill();
            proc->waitForFinished( 1000 );
        }
        proc->deleteLater();
    }

    // flix: the helper is killed, not asked to leave, so the os.RemoveAll in its own
    // exit path never runs. m_torrentDataDir is only set when the data is not being kept
    // (the "keep watched torrents" cap is 0); kept data stays for the next resume and the
    // helper prunes it to the cap.
    if( !m_torrentDataDir.isEmpty() )
    {
        QDir dir( m_torrentDataDir );
        if( dir.exists() && !dir.removeRecursively() )
            msg_Dbg( p_intf, "flixtorrent: could not remove %s", qtu( m_torrentDataDir ) );
        m_torrentDataDir.clear();
    }
}

// the flag the storage page watches. It is not the same as "the helper is running":
// the helper watches this very process and stays alive until we stop it, so its
// existence says nothing about whether the files are in use.
void MainCtx::setTorrentActive( bool active )
{
    if( m_torrentActive == active )
        return;
    m_torrentActive = active;
    emit torrentActiveChanged();
}

void MainCtx::torrentCancel()
{
    stopTorrent();
    QVariantMap status;
    status.insert( QStringLiteral("state"), QStringLiteral("cancelled") );
    emit torrentStatus( status );
}

void MainCtx::torrentStart(const QVariantMap &source)
{
    static const QRegularExpression magnetRe( QStringLiteral("^magnet:\\?xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(&.*)?$") );
    const QString magnet = source.value( QStringLiteral("magnet") ).toString();
    const QString torrentFile = source.value( QStringLiteral("torrentFile") ).toString();
    QVariantMap status;
    const bool validSource = torrentFile.isEmpty() ? magnetRe.match( magnet ).hasMatch()
                                                   : ( torrentFile.endsWith( QLatin1String(".torrent"), Qt::CaseInsensitive )
                                                       && QFileInfo::exists( torrentFile ) );
    if( !validSource || !torrentAvailable() )
    {
        status.insert( QStringLiteral("state"), QStringLiteral("error") );
        status.insert( QStringLiteral("message"), tr("This source cannot be streamed.") );
        emit torrentStatus( status );
        return;
    }
    stopTorrent();
    m_streamBuffer.clear();

    // a new torrent is starting, so any stop still pending from the previous one is
    // now the wrong stop
    ++m_torrentGeneration;

    // what the player needs to know about this stream: resume key, subtitle search info
    m_torrentSession = source;
    {
        const QRegularExpressionMatch hm = magnetRe.match( magnet );
        const QString id = torrentFile.isEmpty() ? hm.captured( 1 ).toLower()
                         : QFileInfo( torrentFile ).fileName() + QString::number( QFileInfo( torrentFile ).size() );
        m_torrentSession.insert( QStringLiteral("resumeKey"),
            QStringLiteral("t:%1:%2").arg( id ).arg( source.value( QStringLiteral("fileIdx"), -1 ).toInt() ) );
        if( !m_torrentSession.contains( QStringLiteral("title") ) )
            m_torrentSession.insert( QStringLiteral("title"),
                source.value( QStringLiteral("meta") ).toMap().value( QStringLiteral("title") ) );
        emit torrentSessionChanged();
    }

    const int fileIdx = source.value( QStringLiteral("fileIdx"), -1 ).toInt();
    // flix: the data is kept per torrent (torrentDir()/data/<info hash>) so a resume finds
    // what it downloaded last time, and the others are pruned to stay under the cap. With
    // the cap at 0 nothing is kept: the helper reports its folder and stopTorrent() removes it.
    const qint64 keepBytes = flixPref( QStringLiteral("torrent/keepBytes"), qint64( 20 ) << 30 ).toLongLong();
    m_torrentDataDir.clear();
    m_streamProc = new QProcess( this );
    QProcess *proc = m_streamProc;

    connect( proc, &QProcess::readyReadStandardError, this, [this, proc]() {
        msg_Dbg( p_intf, "flixtorrent stderr: %s", proc->readAllStandardError().constData() );
    } );
    connect( proc, &QProcess::readyReadStandardOutput, this, [this, proc]() {
        m_streamBuffer += proc->readAllStandardOutput();
        int nl;
        while( ( nl = m_streamBuffer.indexOf( '\n' ) ) >= 0 )
        {
            const QByteArray line = m_streamBuffer.left( nl );
            m_streamBuffer.remove( 0, nl + 1 );
            const QJsonObject o = QJsonDocument::fromJson( line ).object();
            if( o.isEmpty() )
                continue;
            QVariantMap st = o.toVariantMap();
            st.insert( QStringLiteral("state"), o.value( QStringLiteral("event") ).toString() );
            if( st.value( QStringLiteral("state") ).toString() == QLatin1String("progress") )
            {
                m_torrentStats = st;
                emit torrentStatsChanged();
            }
            // a folder that is not being kept is ours to remove when the stream ends
            if( st.value( QStringLiteral("state") ).toString() == QLatin1String("metadata")
                && !st.value( QStringLiteral("kept") ).toBool() )
            {
                const QString dir = QDir::cleanPath( st.value( QStringLiteral("dataDir") ).toString() );
                if( dir.startsWith( QDir::cleanPath( torrentDir() ) + QLatin1Char('/') ) )
                    m_torrentDataDir = dir;
            }
            if( st.value( QStringLiteral("state") ).toString() == QLatin1String("ready") )
            {
                // only ever play what our own helper serves on this machine
                const QUrl url( st.value( QStringLiteral("url") ).toString() );
                if( url.scheme() != QLatin1String("http") || url.host() != QLatin1String("127.0.0.1") )
                    continue;
                // tell the subtitle service what this stream is (the URL has no name)
                const QString name = st.value( QStringLiteral("name") ).toString();
                QVariantMap meta = m_torrentSession.value( QStringLiteral("meta") ).toMap();
                const QVariantMap rel = releaseInfo( name.section( QLatin1Char('/'), -1 ) );
                QJsonObject info;
                info.insert( QStringLiteral("title"), meta.value( QStringLiteral("title") ).toString().isEmpty()
                             ? rel.value( QStringLiteral("title") ).toString() : meta.value( QStringLiteral("title") ).toString() );
                info.insert( QStringLiteral("year"), meta.value( QStringLiteral("year") ).toInt() ? meta.value( QStringLiteral("year") ).toInt()
                             : rel.value( QStringLiteral("year") ).toInt() );
                info.insert( QStringLiteral("season"), meta.value( QStringLiteral("season") ).toInt() ? meta.value( QStringLiteral("season") ).toInt()
                             : rel.value( QStringLiteral("season") ).toInt() );
                info.insert( QStringLiteral("episode"), meta.value( QStringLiteral("episode") ).toInt() ? meta.value( QStringLiteral("episode") ).toInt()
                             : rel.value( QStringLiteral("episode") ).toInt() );
                info.insert( QStringLiteral("imdb"), meta.value( QStringLiteral("imdb") ).toString() );
                info.insert( QStringLiteral("name"), name );
                // the same for every start of this torrent file (the address is not): the
                // subtitle service keeps the subtitle the user downloaded under it
                info.insert( QStringLiteral("key"), m_torrentSession.value( QStringLiteral("resumeKey") ).toString() );
                var_SetString( vlc_object_instance(p_intf), "flix-stream-info",
                               QJsonDocument( info ).toJson( QJsonDocument::Compact ).constData() );
                if( m_torrentSession.value( QStringLiteral("title") ).toString().isEmpty() )
                {
                    m_torrentSession.insert( QStringLiteral("title"), info.value( QStringLiteral("title") ).toString() );
                    emit torrentSessionChanged();
                }
            }
            emit torrentStatus( st );
        }
    } );
    connect( proc, &QProcess::finished, this, [this, proc]( int code, QProcess::ExitStatus ) {
        const QByteArray err = proc->readAllStandardError().trimmed();
        msg_Dbg( p_intf, "flixtorrent stream helper ended: code %d %s", code, err.constData() );
        if( m_streamProc != proc )
            return;
        m_streamProc = nullptr;
        setTorrentActive( false );
        proc->deleteLater();
        if( code != 0 )
        {
            QVariantMap st;
            st.insert( QStringLiteral("state"), QStringLiteral("error") );
            st.insert( QStringLiteral("message"), tr("The torrent helper stopped unexpectedly.") );
            emit torrentStatus( st );
        }
    } );
    connect( proc, &QProcess::errorOccurred, this, [this, proc]( QProcess::ProcessError e ) {
        if( e != QProcess::FailedToStart || m_streamProc != proc )
            return;
        m_streamProc = nullptr;
        setTorrentActive( false );
        proc->deleteLater();
        QVariantMap st;
        st.insert( QStringLiteral("state"), QStringLiteral("error") );
        st.insert( QStringLiteral("message"), tr("Could not start the torrent helper.") );
        emit torrentStatus( st );
    } );

    // leftovers of the old one-folder-per-session layout (data-<time>); kept data now lives
    // under data/<info hash> and is pruned by the helper
    const QDir base( torrentDir() );
    for( const QString &old : base.entryList( { QStringLiteral("data-*") }, QDir::Dirs | QDir::NoDotAndDotDot ) )
        QDir( base.filePath( old ) ).removeRecursively();

    QStringList args { QStringLiteral("stream"),
                       torrentFile.isEmpty() ? QStringLiteral("--magnet") : QStringLiteral("--torrent-file"),
                       torrentFile.isEmpty() ? magnet : torrentFile,
                       QStringLiteral("--cache-root"), torrentDir() + QStringLiteral("/data"),
                       QStringLiteral("--cache-cap"), QString::number( qMax<qint64>( 0, keepBytes ) ),
                       QStringLiteral("--parent-pid"), QString::number( QCoreApplication::applicationPid() ) };
    if( fileIdx >= 0 )
        args << QStringLiteral("--file-idx") << QString::number( fileIdx );
    // continuing: the helper then needs only the header and the index before "ready", since
    // the player opens straight at the saved time (see playTorrentStream)
    if( const double resumeAt = torrentResume(); resumeAt > 0.0 )
        args << QStringLiteral("--start-fraction") << QString::number( resumeAt, 'f', 4 );
    args << trackerArgs();
    args << rateArgs();
    args << streamArgs();
    proc->start( torrentHelper(), args );
}

QVariant MainCtx::flixPref(const QString &key, const QVariant &fallback) const
{
    QSettings settings( torrentDir() + QStringLiteral("/../flix-prefs.ini"), QSettings::IniFormat );
    return settings.value( key, fallback );
}

void MainCtx::setFlixPref(const QString &key, const QVariant &value)
{
    QSettings settings( torrentDir() + QStringLiteral("/../flix-prefs.ini"), QSettings::IniFormat );
    settings.setValue( key, value );
}

bool MainCtx::metaEnabled() const
{
    char *token = var_InheritString( p_intf, "flix-tmdb-token" );
    const bool enabled = token != nullptr && token[0] != '\0';
    free( token );
    return enabled;
}

QVariantMap MainCtx::meta(const QString &name)
{
    if( name.isEmpty() || !metaEnabled() )
        return {};

    const QVariantMap info = releaseInfo( name );
    const QString title = info.value( QStringLiteral("title") ).toString().trimmed();
    if( title.isEmpty() )
        return {};
    const int year = info.value( QStringLiteral("year") ).toInt();
    const bool tv = info.value( QStringLiteral("isEpisode") ).toBool();

    char *lang = var_InheritString( p_intf, "flix-meta-language" );
    const QString language = lang && lang[0] ? qfu( lang ) : QStringLiteral("en-US");
    free( lang );

    // this key names the cache file: the Lua side only sees what we send it
    QString slug;
    for( const QChar c : title.toLower() )
        slug += ( c.unicode() < 128 && c.isLetterOrNumber() ) ? c : QChar('-');
    slug.replace( QRegularExpression( QStringLiteral("-+") ), QStringLiteral("-") );
    slug = slug.left( 80 );
    const QString key = QStringLiteral("%1%2-%3-%4").arg( tv ? QStringLiteral("tv-") : QString(),
        slug ).arg( year ).arg( language.toLower() );

    const QString directory = metaDirectory( p_intf );
    QFile file( directory + QStringLiteral("/movie/") + key + QStringLiteral(".json") );
    if( file.open( QIODevice::ReadOnly ) )
    {
        const QJsonObject o = QJsonDocument::fromJson( file.readAll() ).object();
        file.close();
        const qint64 age = QDateTime::currentSecsSinceEpoch() - qint64( o.value( QStringLiteral("fetched") ).toDouble() );
        // records written before the age certification was fetched have no such field: refresh them
        const bool stale = o.value( QStringLiteral("found") ).toBool()
                         ? ( age > 14 * 86400 || !o.contains( QStringLiteral("certification") ) )
                         : age > 1 * 86400;
        if( !o.isEmpty() )
        {
            // stale-while-revalidate: show what we have at once, refresh it in the background
            if( !stale )
                return metaRecordToMap( o, directory );
            static QSet<QString> refreshedThisSession;      // one refresh try per title and session
            if( !m_metaPending.contains( key ) && o.value( QStringLiteral("found") ).toBool()
                && !refreshedThisSession.contains( key ) )
            {
                refreshedThisSession.insert( key );
                QVariantMap refresh;
                refresh.insert( QStringLiteral("key"), key );
                refresh.insert( QStringLiteral("title"), title );
                refresh.insert( QStringLiteral("year"), year );
                refresh.insert( QStringLiteral("season"), info.value( QStringLiteral("season") ) );
                refresh.insert( QStringLiteral("episode"), info.value( QStringLiteral("episode") ) );
                queueMeta( key, refresh );
                return metaRecordToMap( o, directory );
            }
        }
    }

    // not cached: ask the service (batched)
    if( !m_metaPending.contains( key ) )
    {
        QVariantMap req;
        req.insert( QStringLiteral("key"), key );
        req.insert( QStringLiteral("title"), title );
        req.insert( QStringLiteral("year"), year );
        req.insert( QStringLiteral("season"), info.value( QStringLiteral("season") ) );
        req.insert( QStringLiteral("episode"), info.value( QStringLiteral("episode") ) );
        m_metaPending.insert( key, req );
        if( !m_metaTimer )
        {
            m_metaTimer = new QTimer( this );
            m_metaTimer->setSingleShot( true );
            connect( m_metaTimer, &QTimer::timeout, this, &MainCtx::flushMetaRequests );
        }
        m_metaTimer->start( 300 );
    }
    return {};
}

void MainCtx::flushMetaRequests()
{
    libvlc_int_t *libvlc = vlc_object_instance( p_intf );
    QJsonArray list;

    // keep what the service has not picked up yet
    char *previous = var_GetString( libvlc, "flix-meta-request" );
    if( previous != nullptr && previous[0] != '\0' )
        list = QJsonDocument::fromJson( QByteArray( previous ) ).array();
    free( previous );

    for( const QVariant &req : std::as_const( m_metaPending ) )
        list.append( QJsonObject::fromVariantMap( req.toMap() ) );
    m_metaPending.clear();
    var_SetString( libvlc, "flix-meta-request", QJsonDocument( list ).toJson( QJsonDocument::Compact ).constData() );
}

static QString metaLanguage( qt_intf_t *intf )
{
    char *lang = var_InheritString( intf, "flix-meta-language" );
    const QString language = lang && lang[0] ? qfu( lang ) : QStringLiteral("en-US");
    free( lang );
    return language;
}

void MainCtx::queueMeta(const QString &key, const QVariantMap &req)
{
    if( m_metaPending.contains( key ) )
        return;
    m_metaPending.insert( key, req );
    if( !m_metaTimer )
    {
        m_metaTimer = new QTimer( this );
        m_metaTimer->setSingleShot( true );
        connect( m_metaTimer, &QTimer::timeout, this, &MainCtx::flushMetaRequests );
    }
    m_metaTimer->start( 300 );
}

static QHash<int, QString> genreNames( const QString &directory, const QString &type )
{
    QHash<int, QString> names;
    QFile file( directory + QStringLiteral("/genres.json") );
    if( !file.open( QIODevice::ReadOnly ) )
        return names;
    const QJsonArray list = QJsonDocument::fromJson( file.readAll() ).object().value( type ).toArray();
    for( const QJsonValue &v : list )
        names.insert( v.toObject().value( QStringLiteral("id") ).toInt(),
                      v.toObject().value( QStringLiteral("name") ).toString() );
    return names;
}

QVariantList MainCtx::genres(const QString &type) const
{
    QVariantList result;
    QFile file( metaDirectory( p_intf ) + QStringLiteral("/genres.json") );
    if( !file.open( QIODevice::ReadOnly ) )
        return result;
    const QJsonArray list = QJsonDocument::fromJson( file.readAll() ).object()
        .value( type == QLatin1String("tv") ? QStringLiteral("tv") : QStringLiteral("movie") ).toArray();
    for( const QJsonValue &v : list )
    {
        QVariantMap g;
        g.insert( QStringLiteral("id"), v.toObject().value( QStringLiteral("id") ).toInt() );
        g.insert( QStringLiteral("name"), v.toObject().value( QStringLiteral("name") ).toString() );
        result.append( g );
    }
    return result;
}

QVariantMap MainCtx::discover(const QVariantMap &params)
{
    QVariantMap result;
    result.insert( QStringLiteral("ready"), false );
    result.insert( QStringLiteral("items"), QVariantList() );
    result.insert( QStringLiteral("page"), 1 );
    result.insert( QStringLiteral("totalPages"), 1 );
    if( !metaEnabled() )
        return result;

    const QString language = metaLanguage( p_intf );
    const QString type = params.value( QStringLiteral("type") ).toString() == QLatin1String("tv")
                       ? QStringLiteral("tv") : QStringLiteral("movie");

    // the key names the cache file: same search and language, same file
    const QByteArray canonical = QJsonDocument( QJsonObject::fromVariantMap( params ) ).toJson( QJsonDocument::Compact )
                               + language.toUtf8();
    const QString key = QStringLiteral("d-") + QString::fromLatin1(
        QCryptographicHash::hash( canonical, QCryptographicHash::Sha1 ).toHex().left( 20 ) );

    const QString directory = metaDirectory( p_intf );
    QFile file( directory + QStringLiteral("/discover/") + key + QStringLiteral(".json") );
    bool refresh = true;
    if( file.open( QIODevice::ReadOnly ) )
    {
        const QJsonObject o = QJsonDocument::fromJson( file.readAll() ).object();
        file.close();
        if( !o.isEmpty() )
        {
            const qint64 age = QDateTime::currentSecsSinceEpoch() - qint64( o.value( QStringLiteral("fetched") ).toDouble() );
            refresh = age > 6 * 3600;
            const QHash<int, QString> names = genreNames( directory, type );
            QVariantList items;
            for( const QJsonValue &v : o.value( QStringLiteral("items") ).toArray() )
            {
                const QJsonObject r = v.toObject();
                QVariantMap m;
                m.insert( QStringLiteral("tmdbId"), r.value( QStringLiteral("tmdb_id") ).toInt() );
                m.insert( QStringLiteral("mediaType"), r.value( QStringLiteral("media_type") ).toString() );
                m.insert( QStringLiteral("title"), r.value( QStringLiteral("title") ).toString() );
                m.insert( QStringLiteral("year"), r.value( QStringLiteral("year") ).toInt() );
                m.insert( QStringLiteral("overview"), r.value( QStringLiteral("overview") ).toString() );
                m.insert( QStringLiteral("rating"), r.value( QStringLiteral("rating") ).toDouble() );
                m.insert( QStringLiteral("poster"), metaFileUrl( directory, r.value( QStringLiteral("poster") ).toString() ) );
                m.insert( QStringLiteral("backdrop"), QString() );
                m.insert( QStringLiteral("imdbId"), QString() );
                QStringList genreList;
                for( const QJsonValue &g : r.value( QStringLiteral("genre_ids") ).toArray() )
                    if( names.contains( g.toInt() ) )
                        genreList << names.value( g.toInt() );
                m.insert( QStringLiteral("genres"), genreList );
                items.append( m );
            }
            result.insert( QStringLiteral("ready"), true );
            result.insert( QStringLiteral("items"), items );
            result.insert( QStringLiteral("page"), o.value( QStringLiteral("page") ).toInt( 1 ) );
            result.insert( QStringLiteral("totalPages"), o.value( QStringLiteral("total_pages") ).toInt( 1 ) );
        }
    }

    if( refresh )
    {
        QVariantMap req;
        req.insert( QStringLiteral("key"), key );
        req.insert( QStringLiteral("kind"), QStringLiteral("discover") );
        req.insert( QStringLiteral("params"), params );
        queueMeta( key, req );
    }
    return result;
}

QVariantMap MainCtx::webDetail(int tmdbId, const QString &type)
{
    if( tmdbId <= 0 || !metaEnabled() )
        return {};

    const QString kind = type == QLatin1String("tv") ? QStringLiteral("tv") : QStringLiteral("movie");
    const QString key = QStringLiteral("w-%1-%2-%3").arg( kind ).arg( tmdbId ).arg( metaLanguage( p_intf ).toLower() );

    const QString directory = metaDirectory( p_intf );
    QFile file( directory + QStringLiteral("/movie/") + key + QStringLiteral(".json") );
    if( file.open( QIODevice::ReadOnly ) )
    {
        const QJsonObject o = QJsonDocument::fromJson( file.readAll() ).object();
        file.close();
        const qint64 age = QDateTime::currentSecsSinceEpoch() - qint64( o.value( QStringLiteral("fetched") ).toDouble() );
        if( !o.isEmpty() && age < 30 * 86400 )
            return metaRecordToMap( o, directory );
    }

    QVariantMap req;
    req.insert( QStringLiteral("key"), key );
    req.insert( QStringLiteral("kind"), QStringLiteral("detail") );
    req.insert( QStringLiteral("tmdb_id"), tmdbId );
    req.insert( QStringLiteral("type"), kind );
    queueMeta( key, req );
    return {};
}

QVariantList MainCtx::topTen() const
{
    QVariantList result;
    const QString directory = metaDirectory( p_intf );
    QFile file( directory + QStringLiteral("/top10.json") );
    if( !file.open( QIODevice::ReadOnly ) )
        return result;
    const QJsonArray items = QJsonDocument::fromJson( file.readAll() ).object().value( QStringLiteral("items") ).toArray();
    for( const QJsonValue &v : items )
    {
        QVariantMap m = metaRecordToMap( v.toObject(), directory );
        m.insert( QStringLiteral("rank"), v.toObject().value( QStringLiteral("rank") ).toInt() );
        if( !m.value( QStringLiteral("poster") ).toString().isEmpty() )
            result.append( m );
    }
    return result;
}

static bool validImdbId( const QString &id )
{
    return QRegularExpression( QStringLiteral("^tt\\d{5,10}$") ).match( id ).hasMatch();
}

QUrl MainCtx::imdbUrl(const QString &imdbId) const
{
    return validImdbId( imdbId ) ? QUrl( QStringLiteral("https://www.imdb.com/title/") + imdbId + QLatin1Char('/') )
                                 : QUrl();
}

QUrl MainCtx::topTenUrl(const QString &imdbId) const
{
    if( !validImdbId( imdbId ) )
        return QUrl();
    char *target = var_InheritString( p_intf, "flix-top10-target" );
    const bool imdb = target && qstrcmp( target, "imdb" ) == 0;
    free( target );
    if( imdb )
        return imdbUrl( imdbId );
    return QUrl( QStringLiteral("https://heartivelovestv.pages.dev/torrents/?id=") + imdbId );
}

bool MainCtx::openExternal(const QUrl &url) const
{
    if( !url.isValid() || ( url.scheme() != QLatin1String("https") && url.scheme() != QLatin1String("http") ) )
        return false;
    return QDesktopServices::openUrl( url );
}

QString MainCtx::cleanTitle(const QString &name) const
{
    if (name.isEmpty())
        return name;

    char *display = vlc_release_name_display(qtu(name));
    if (display == nullptr)
        return name;

    const QString result = qfu(display);
    free(display);
    return result;
}

void MainCtx::setPlayerPlaylistWidth( double factor )
{
    if (factor > 0.0)
    {
        m_playerPlaylistWidth = factor;
        emit playerPlaylistWidthChanged(factor);
    }
}

void MainCtx::setbgCone(bool bgCone)
{
    if (m_bgCone == bgCone)
        return;

    m_bgCone = bgCone;

    emit bgConeToggled();
}

void MainCtx::setMinimalView(bool enable)
{
    if (m_mainInterfaceModes.testFlag(MAININTERFACE_MODE_MINIMAL) == enable)
        return;

    m_mainInterfaceModes.setFlag(MAININTERFACE_MODE_MINIMAL, enable);
    emit mainInterfaceModesChanged(m_mainInterfaceModes);
}

void MainCtx::setPlayerView(bool enable)
{
    if (m_mainInterfaceModes.testFlag(MAININTERFACE_MODE_PLAYER) == enable)
        return;

    m_mainInterfaceModes.setFlag(MAININTERFACE_MODE_PLAYER, enable);
    emit mainInterfaceModesChanged(m_mainInterfaceModes);
}

void MainCtx::setShowRemainingTime( bool show )
{
    m_showRemainingTime = show;
    emit showRemainingTimeChanged(show);
}

void MainCtx::setGridView(bool asGrid)
{
    m_gridView = asGrid;
    emit gridViewChanged( asGrid );
}

void MainCtx::setGrouping(Grouping grouping)
{
    m_grouping = grouping;

    emit groupingChanged(grouping);
}

void MainCtx::setAlbumSections(bool enabled)
{
    if (m_albumSections == enabled)
        return;

    m_albumSections = enabled;
    emit albumSectionsChanged(enabled);
}

void MainCtx::setLyricsMode(bool enabled)
{
    if (m_lyricsMode == enabled)
        return;

    m_lyricsMode = enabled;
    emit lyricsModeChanged(enabled);
}

void MainCtx::setInterfaceAlwaysOnTop( bool on_top )
{
    if (b_interfaceOnTop == on_top)
        return;

    b_interfaceOnTop = on_top;
    emit interfaceAlwaysOnTopChanged(on_top);
}

bool MainCtx::hasEmbededVideo() const
{
    return m_videoSurfaceProvider && m_videoSurfaceProvider->hasVideoEmbed();
}

void MainCtx::setVideoSurfaceProvider(VideoSurfaceProvider* videoSurfaceProvider)
{
    if (m_videoSurfaceProvider)
        disconnect(m_videoSurfaceProvider, &VideoSurfaceProvider::hasVideoEmbedChanged, this, &MainCtx::hasEmbededVideoChanged);
    m_videoSurfaceProvider = videoSurfaceProvider;
    if (m_videoSurfaceProvider)
        connect(m_videoSurfaceProvider, &VideoSurfaceProvider::hasVideoEmbedChanged,
                this, &MainCtx::hasEmbededVideoChanged,
                Qt::QueuedConnection);
    emit hasEmbededVideoChanged(m_videoSurfaceProvider && m_videoSurfaceProvider->hasVideoEmbed());
}

QJSValue MainCtx::urlListToMimeData(const QJSValue &array) {
    // NOTE: Due to a Qt regression since 17318c4
    //       (Nov 11, 2022), it is not possible to
    //       use RFC-2483 compliant string here.
    //       This regression was later corrected by
    //       c25f53b (Jul 31, 2024).
    // NOTE: Qt starts supporting string list since
    //       17318c4, so starting from 6.5.0 a string
    //       list can be used which is not affected
    //       by the said issue. For Qt versions below
    //       6.5.0, use byte array which is used as is
    //       by Qt.
    assert(array.property("length").toInt() > 0);

    QJSEngine* const engine = qjsEngine(this);
    assert(engine);

    QJSValue data;
#if QT_VERSION < QT_VERSION_CHECK(6, 5, 0)
    QString string;
    for (int i = 0; i < array.property(QStringLiteral("length")).toInt(); ++i)
    {
        QString decodedUrl;
        const QJSValue element = array.property(i);
        if (element.isUrl())
            // QJSValue does not have `toUrl()`
            decodedUrl = QJSManagedValue(element, engine).toUrl().toString(QUrl::FullyEncoded);
        else if (element.isString())
            // If the element is string, we assume it is already encoded
            decodedUrl = element.toString();
        else if (element.isVariant())
        {
            const QVariant variant = element.toVariant();
            if (variant.typeId() == QMetaType::QUrl)
                decodedUrl = variant.toUrl().toString(QUrl::FullyEncoded);
            else if (variant.typeId() == QMetaType::QString)
                decodedUrl = variant.toString();
            else
                Q_UNREACHABLE();
        }
        else
            Q_UNREACHABLE(); // Assertion failure in debug builds
        string += decodedUrl + QStringLiteral("\r\n");
    }
    string.chop(2);
    data = engine->toScriptValue(string);
#else
    data = array;
#endif
    QJSValue ret = engine->newObject();
    ret.setProperty(QStringLiteral("text/uri-list"), data);
    return ret;
}

VideoSurfaceProvider* MainCtx::getVideoSurfaceProvider() const
{
    return m_videoSurfaceProvider;
}

/************************************************************************
 * Events stuff
 ************************************************************************/

void MainCtx::onWindowClose( QWindow* )
{
    PlaylistController* playlistController = p_intf->p_mainPlaylistController;
    PlayerController* playerController = p_intf->p_mainPlayerController;

    if (m_videoSurfaceProvider)
        m_videoSurfaceProvider->onWindowClosed();
    //We need to make sure that noting is playing anymore otherwise the vout will be closed
    //after the main interface, and it requires (at least with OpenGL) that the OpenGL context
    //from the main window is still valid.
    //vlc_window_ReportClose is currently stubbed
    if (playerController && playerController->hasVideoOutput()) {
        connect(playerController, &PlayerController::playingStateChanged, [this](PlayerController::PlayingState state){
            if (state == PlayerController::PLAYING_STATE_STOPPED) {
                emit askToQuit();
            }
        });
        playlistController->stop();
    }
    else
    {
        emit askToQuit(); /* ask THEDP to quit, so we have a unique method */
    }
}

void MainCtx::toggleToolbarMenu()
{
    setHasToolbarMenu(!m_hasToolbarMenu);
}

void MainCtx::toggleInterfaceFullScreen()
{
    emit setInterfaceFullScreen( m_windowVisibility != QWindow::FullScreen );
}

void MainCtx::emitBoss()
{
    emit askBoss();
}

void MainCtx::emitShow()
{
    emit askShow();
}

void MainCtx::answerSubtitleOffer(int fileId, bool accept)
{
    const QString reply = QStringLiteral("%1:%2").arg(accept ? QStringLiteral("yes") : QStringLiteral("no")).arg(fileId);
    var_SetString( vlc_object_instance(p_intf), "flix-sub-reply", qtu(reply) );
}

void MainCtx::emitRaise()
{
    emit askRaise();
}

VLCVarChoiceModel* MainCtx::getExtraInterfaces()
{
    return m_extraInterfaces;
}

bool MainCtx::pasteFromClipboard()
{
    assert(qApp);
    const QClipboard *const clipboard = qApp->clipboard();
    if (Q_UNLIKELY(!clipboard))
        return false;
    const QMimeData *mimeData = clipboard->mimeData(QClipboard::Selection);
    if (!mimeData || !mimeData->hasUrls())
        mimeData = clipboard->mimeData(QClipboard::Clipboard);

    if (Q_UNLIKELY(!mimeData))
        return false;

    QList<QUrl> urlList = mimeData->urls();
    QString text = mimeData->text();

    if (urlList.count() > 1 || text.contains('\n'))
    {
        // NOTE: The reason that mime data for `text/uri-list` is not used
        //       directly as the placeholder of the input dialog instead of
        //       re-constructing is to decode the urls in the list.
        QString placeholder;

        if (urlList.isEmpty())
        {
            placeholder = std::move(text);
        }
        else
        {
            for (const auto& i : urlList)
                placeholder += i.toString(QUrl::PrettyDecoded) + '\n';
            placeholder.chop(1);
        }

        bool ok = false;
        const QString ret = QInputDialog::getMultiLineText(nullptr,
                                                           qtr("Paste from clipboard"),
                                                           qtr("Do you want to enqueue the following URLs into the play queue?"),
                                                           placeholder,
                                                           &ok);
        if (!ok)
            return false;

        for (const auto& i : QStringView(ret).split('\n'))
        {
            if (i.length() > 0)
                THEMPL->append(i.trimmed().toString(), false);
        }

        return true;
    }
    else if ((urlList.count() == 1) || mimeData->hasText())
    {
        THEDP->openUrlDialog();
        return true;
    }

    return false;
}

/*****************************************************************************
 * PopupMenuCB: callback triggered by the intf-popupmenu playlist variable.
 *  We don't show the menu directly here because we don't want the
 *  caller to block for a too long time.
 *****************************************************************************/
static int PopupMenuCB( vlc_object_t *, const char *,
                        vlc_value_t, vlc_value_t new_val, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;

    if( p_intf->pf_show_dialog )
    {
        p_intf->pf_show_dialog( p_intf->intf, INTF_DIALOG_POPUPMENU,
                                new_val.b_bool, NULL );
    }

    return VLC_SUCCESS;
}

/*****************************************************************************
 * IntfShowCB: callback triggered by the intf-toggle-fscontrol libvlc variable.
 *****************************************************************************/
/* flix: called from the Lua subtitle service's thread with the JSON of an offer */
static int SubtitleOfferCB( vlc_object_t *, const char *,
                            vlc_value_t, vlc_value_t new_val, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;
    if( new_val.psz_string != NULL && new_val.psz_string[0] != '\0' && p_intf->p_mi != NULL )
        p_intf->p_mi->emitSubtitleOffer( qfu( new_val.psz_string ) );

    return VLC_SUCCESS;
}

/* flix: called from the Lua service's thread with the key of a new cache entry */
static int AccountResultCB( vlc_object_t *, const char *,
                            vlc_value_t, vlc_value_t new_val, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;
    if( new_val.psz_string != NULL && new_val.psz_string[0] != '\0' && p_intf->p_mi != NULL )
        p_intf->p_mi->emitAccountResult( qfu( new_val.psz_string ) );

    return VLC_SUCCESS;
}

static int MetaUpdateCB( vlc_object_t *, const char *,
                         vlc_value_t, vlc_value_t new_val, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;
    if( new_val.psz_string != NULL && new_val.psz_string[0] != '\0' && p_intf->p_mi != NULL )
        p_intf->p_mi->emitMetaUpdate( qfu( new_val.psz_string ) );

    return VLC_SUCCESS;
}

static int UpdateCB( vlc_object_t *, const char *,
                     vlc_value_t, vlc_value_t, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;
    if( p_intf->p_mi != NULL )
        p_intf->p_mi->emitUpdateChanged();
    return VLC_SUCCESS;
}

// the newer release the Lua service found ({version, url}), empty when there is none. Read
// from the variable rather than kept from the signal: the service can find it before the
// Home page is there to listen.
QVariantMap MainCtx::updateInfo() const
{
    char *text = var_GetString( vlc_object_instance(p_intf), "flix-update" );
    if( text == nullptr )
        return {};
    const QVariantMap info = QJsonDocument::fromJson( QByteArray( text ) ).object().toVariantMap();
    free( text );
    const QUrl url( info.value( QStringLiteral("url") ).toString() );
    // only ever send the user to this project's own releases
    if( url.scheme() != QLatin1String("https") || url.host() != QLatin1String("github.com") )
        return {};
    return info;
}

static int IntfShowCB( vlc_object_t *, const char *,
                       vlc_value_t, vlc_value_t, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;
    p_intf->p_mi->emitShow();

    return VLC_SUCCESS;
}

/*****************************************************************************
 * IntfRaiseMainCB: callback triggered by the intf-show-main libvlc variable.
 *****************************************************************************/
static int IntfRaiseMainCB( vlc_object_t *, const char *,
                            vlc_value_t, vlc_value_t, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;
    p_intf->p_mi->emitRaise();

    return VLC_SUCCESS;
}

/*****************************************************************************
 * IntfBossCB: callback triggered by the intf-boss libvlc variable.
 *****************************************************************************/
static int IntfBossCB( vlc_object_t *, const char *,
                       vlc_value_t, vlc_value_t, void *param )
{
    qt_intf_t *p_intf = (qt_intf_t *)param;
    p_intf->p_mi->emitBoss();

    return VLC_SUCCESS;
}

bool MainCtx::acrylicActive() const
{
    return m_acrylicActive;
}

void MainCtx::setAcrylicActive(bool newAcrylicActive)
{
    if (m_acrylicActive == newAcrylicActive)
        return;

    m_acrylicActive = newAcrylicActive;
    emit acrylicActiveChanged();
}

bool MainCtx::preferHotkeys() const
{
    return m_preferHotkeys;
}

void MainCtx::setPreferHotkeys(bool enable)
{
    if (m_preferHotkeys == enable)
        return;

    m_preferHotkeys = enable;

    emit preferHotkeysChanged();
}

QWindow *MainCtx::intfMainWindow() const
{
    if (p_intf->p_compositor)
        return p_intf->p_compositor->interfaceMainWindow();
    else
        return nullptr;
}

QVariant MainCtx::settingValue(const QString &key, const QVariant &defaultValue) const
{
    return settings->value(key, defaultValue);
}

void MainCtx::setSettingValue(const QString &key, const QVariant &value)
{
    settings->setValue(key, value);
}

void MainCtx::setAttachedToolTip(QObject *toolTip)
{
    // See QQuickToolTipAttachedPrivate::instance(bool create)
    assert(toolTip);

    // Prevent possible invalid down-casting:
    assert(toolTip->inherits("QQuickToolTip"));

    QQmlEngine* const engine = qmlEngine(toolTip);
    assert(engine);
    assert(engine->objectOwnership(toolTip) == QQmlEngine::ObjectOwnership::JavaScriptOwnership);

    // Dynamic internal property:
#if QT_VERSION < QT_VERSION_CHECK(6, 12, 0)
    static const char* const name = "_q_QQuickToolTip";
#else
    static const char* const name = "_q_shared_QQuickToolTip";
#endif

    if (const auto obj = engine->property(name).value<QObject *>())
    {
        if (engine->objectOwnership(obj) == QQmlEngine::ObjectOwnership::CppOwnership)
            obj->deleteLater();
    }

    // setProperty() will return false, so there is no
    // need to check the return value:
    engine->setProperty(name, QVariant::fromValue(toolTip));

    // Check if the attached tooltip is actually the
    // one that is set
#ifndef NDEBUG
    QMetaObject::invokeMethod(toolTip, [toolTip]() {
        const auto engine = qmlEngine(toolTip);
        if (Q_UNLIKELY(!engine)) // Very unlikely, if not impossible
            return;
        QQmlComponent component(engine);
        component.setData(QByteArrayLiteral("import QtQuick; import QtQuick.Controls; Item { }"), {});
        QObject* const obj = component.create();
        assert(obj);
        // Consider disabling setting of custom attached
        // tooltip if the following assertion fails:
        if (QQmlProperty::read(obj, QStringLiteral("ToolTip.toolTip"), qmlContext(obj)).value<QObject*>() != toolTip)
            qmlWarning(obj) << "Could not set self as custom ToolTip!";
        obj->deleteLater();
    }, Qt::QueuedConnection);
#endif
}

MainCtx::MainInterfaceMode MainCtx::getEffectiveMainInterfaceMode() const {
    //priority applies across modes
    if (m_mainInterfaceModes & MainCtx::MAININTERFACE_MODE_MINIMAL)
        return MAININTERFACE_MODE_MINIMAL;
    else if (m_mainInterfaceModes & MAININTERFACE_MODE_PLAYER)
        return MAININTERFACE_MODE_PLAYER;
    else if (m_mainInterfaceModes & MAININTERFACE_MODE_MAINDISPLAY)
        return MAININTERFACE_MODE_MAINDISPLAY;
    else
        return MAININTERFACE_MODE_INVALID;
}

double MainCtx::dp(const double px, const double scale)
{
    return std::round(px * scale);
}

double MainCtx::dp(const double px) const
{
    return dp(px, m_intfScaleFactor);
}

bool MainCtx::useXmasCone() const
{
    return (QDate::currentDate().dayOfYear() >= QT_XMAS_JOKE_DAY)
            && var_InheritBool( p_intf, "qt-icon-change" );
}

bool WindowStateHolder::holdFullscreen(QWindow *window, Source source, bool hold)
{
    QVariant prop = window->property("__windowFullScreen");
    bool ok = false;
    unsigned fullscreenCounter = prop.toUInt(&ok);
    if (!ok)
        fullscreenCounter = 0;

    if (hold)
        fullscreenCounter |= source;
    else
        fullscreenCounter &= ~source;

    Qt::WindowStates oldflags = window->windowStates();
    Qt::WindowStates newflags;

    if( fullscreenCounter != 0 )
        newflags = oldflags | Qt::WindowFullScreen;
    else
        newflags = oldflags & ~Qt::WindowFullScreen;

    window->setProperty("__windowFullScreen", QVariant::fromValue(fullscreenCounter));

    if( newflags != oldflags )
    {
        window->setWindowStates( newflags );
    }

    return fullscreenCounter != 0;
}

bool WindowStateHolder::holdOnTop(QWindow *window, Source source, bool hold)
{
    QVariant prop = window->property("__windowOnTop");
    bool ok = false;
    unsigned onTopCounter = prop.toUInt(&ok);
    if (!ok)
        onTopCounter = 0;

    if (hold)
        onTopCounter |= source;
    else
        onTopCounter &= ~source;

#ifdef _WIN32
    if (!window->handle()) // do not call hold on top if there is no platform window
        return false;
#endif

    if( onTopCounter != 0 )
    {
#ifdef _WIN32
        // Qt::WindowStaysOnTopHint is broken on Windows: QTBUG-133034, QTBUG-132522.
        // Reported to be fixed by Qt 6.9, but needs additional checking if the solution does not interfere with `CSDWin32EventHandler`.
        SetWindowPos(reinterpret_cast<HWND>(window->winId()), HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
#else
        window->setFlag(Qt::WindowStaysOnTopHint, true);
#endif
    }
    else
    {
#ifdef _WIN32
        // Qt::WindowStaysOnTopHint is broken on Windows: QTBUG-133034, QTBUG-132522.
        // Reported to be fixed by Qt 6.9, but needs additional checking if the solution does not interfere with `CSDWin32EventHandler`.
        SetWindowPos(reinterpret_cast<HWND>(window->winId()), HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
#else
        window->setFlag(Qt::WindowStaysOnTopHint, false);
#endif
    }

    window->setProperty("__windowOnTop", QVariant::fromValue(onTopCounter));

    return onTopCounter != 0;
}

double MainCtx::artistAlbumsWidth() const
{
    return dp(m_artistAlbumsWidth);
}

void MainCtx::setArtistAlbumsWidth(double newArtistAlbumsWidth)
{
    double unscaledValue = newArtistAlbumsWidth / getIntfScaleFactor();
    if (qFuzzyCompare(m_artistAlbumsWidth, unscaledValue))
        return;

    m_artistAlbumsWidth = unscaledValue;
    emit artistAlbumsWidthChanged( dp(m_artistAlbumsWidth) );
}

#ifdef UPDATE_CHECK
UpdateModel* MainCtx::getUpdateModel() const
{
    if (!m_updateModel)
    {
        m_updateModel = std::make_unique<UpdateModel>(p_intf);

        connect(m_updateModel.get(), &UpdateModel::updateStatusChanged, this, [this](){
            // No-op, modern update pane opens itself automatically when status changes.
            // However, the old update dialog is used as fallback in case for any reason
            // the modern pane is not available.

            const auto openLegacyDialogIfNecessary = [&]() {
                // Fallback:

                if (Q_LIKELY(p_intf &&
                             p_intf->p_compositor &&
                             p_intf->p_compositor->quickWindow() &&
                             p_intf->p_compositor->quickWindow()->contentItem()))
                {
                    const auto target = p_intf->p_compositor->quickWindow()->contentItem();
                    QMetaObject::invokeMethod(target, [target]() {
                        const auto updatePaneLoader = target->findChild<QQuickItem*>(QStringLiteral("updatePaneLoader"));
                        if (!updatePaneLoader || (updatePaneLoader->property("status").toInt() != 1 /* Loader.Ready */))
                        {
                            qDebug("No acknowledgement from the modern update loader, falling back to the old update dialog.");
                            THEDP->updateDialog(DialogsProvider::Show);
                        }
                    }, Qt::QueuedConnection);
                }
                else
                {
                    qDebug("Compositor is not available, falling back to the old update dialog.");
                    THEDP->updateDialog();
                }
            };

            if (m_updateModel->explicitCheck())
            {
                if (m_updateModel->updateStatus() != UpdateModel::Unchecked)
                    openLegacyDialogIfNecessary();
            }
            else
            {
                switch (m_updateModel->updateStatus())
                {
                case UpdateModel::UpToDate:
                case UpdateModel::Unchecked:
                case UpdateModel::Checking:
                    break;
                case UpdateModel::NeedUpdate:
                    qWarning() << "Need update";
                    [[fallthrough]];
                default:
                    openLegacyDialogIfNecessary();
                }
            }
        });
    }

    return m_updateModel.get();
}
#endif
