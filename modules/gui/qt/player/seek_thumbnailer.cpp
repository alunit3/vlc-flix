/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "seek_thumbnailer.hpp"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QPointer>

#include "qt.hpp"
#include "maininterface/mainctx.hpp"
#include "player/player_controller.hpp"

#include <vlc_configuration.h>
#include <vlc_input_item.h>
#include <vlc_preparser.h>

/* Data handed to the preparser callback, which runs on another thread. */
struct SeekThumbnailer::Job
{
    QPointer<SeekThumbnailer> owner;
    int bucket;
    int generation;
    QByteArray path;        // must outlive the request: the thumbnailer reads file_path
};

SeekThumbnailer::SeekThumbnailer(QObject *parent)
    : QObject(parent)
{
}

SeekThumbnailer::~SeekThumbnailer()
{
    if (m_preparser != nullptr)
    {
        /* callbacks of cancelled requests only post a queued call guarded by a QPointer */
        vlc_preparser_Cancel(m_preparser, nullptr);
        vlc_preparser_Delete(m_preparser);
    }
}

void SeekThumbnailer::setCtx(MainCtx *ctx)
{
    if (m_ctx == ctx)
        return;
    m_ctx = ctx;
    emit ctxChanged();
}

void SeekThumbnailer::setPlayer(PlayerController *player)
{
    if (m_player == player)
        return;

    if (m_player != nullptr)
        disconnect(m_player, nullptr, this, nullptr);

    m_player = player;

    if (m_player != nullptr)
    {
        connect(m_player, &PlayerController::inputChanged, this, &SeekThumbnailer::onInputChanged);
        connect(m_player, &PlayerController::hasVideoOutputChanged, this, &SeekThumbnailer::updateAvailable);
        onInputChanged();
    }
    emit playerChanged();
}

void SeekThumbnailer::onInputChanged()
{
    ++m_generation;
    m_wanted = -1;
    m_mediaUrl = m_player ? m_player->getUrl() : QUrl();
    m_mediaKey = QString::fromLatin1(
        QCryptographicHash::hash(m_mediaUrl.toEncoded(), QCryptographicHash::Sha1).toHex().left(12));
    setSource(QUrl());
    updateAvailable();
}

void SeekThumbnailer::updateAvailable()
{
    const bool available = m_player != nullptr
            && m_player->hasVideoOutput()
            && m_mediaUrl.isLocalFile();

    if (available == m_available)
        return;
    m_available = available;
    emit availableChanged();
}

QString SeekThumbnailer::fileFor(int bucket) const
{
    return QStringLiteral("%1/%2_%3.jpg").arg(m_cacheDir, m_mediaKey).arg(bucket);
}

bool SeekThumbnailer::ensurePreparser()
{
    if (m_preparser != nullptr)
        return true;
    if (m_ctx == nullptr || m_ctx->getIntf() == nullptr)
        return false;

    /* previews live in the cache folder, emptied at the first use */
    char *cache = config_GetUserDir(VLC_CACHE_DIR);
    if (cache == nullptr)
        return false;
    m_cacheDir = qfu(cache) + QStringLiteral("/seekthumbs");
    free(cache);

    QDir dir(m_cacheDir);
    if (dir.exists())
        dir.removeRecursively();
    if (!QDir().mkpath(m_cacheDir))
        return false;

    struct vlc_preparser_cfg cfg{};
    cfg.types = VLC_PREPARSER_TYPE_THUMBNAIL_TO_FILES;
    cfg.max_thumbnailer_threads = 1;
    cfg.timeout = VLC_TICK_FROM_SEC(8);
    cfg.external_process = false;

    m_preparser = vlc_preparser_New(VLC_OBJECT(vlc_object_instance(m_ctx->getIntf())), &cfg);
    return m_preparser != nullptr;
}

void SeekThumbnailer::request(double seconds)
{
    if (!m_available || seconds < 0)
        return;

    const int bucket = static_cast<int>(seconds / bucketSeconds) * bucketSeconds;
    m_wanted = bucket;

    /* already made: show it right away */
    const QString path = fileFor(bucket);
    if (!m_cacheDir.isEmpty() && QFileInfo::exists(path))
    {
        setSource(QUrl::fromLocalFile(path));
        return;
    }

    if (m_inflight < 0)
        startNext();
}

void SeekThumbnailer::clear()
{
    m_wanted = -1;
}

void SeekThumbnailer::setSource(const QUrl &source)
{
    if (m_source == source)
        return;
    m_source = source;
    emit sourceChanged();
}

void SeekThumbnailer::startNext()
{
    if (m_inflight >= 0 || m_wanted < 0 || !m_available || !ensurePreparser())
        return;

    const int bucket = m_wanted;
    const QString path = fileFor(bucket);
    if (QFileInfo::exists(path))
    {
        setSource(QUrl::fromLocalFile(path));
        return;
    }

    input_item_t *item = input_item_New(m_mediaUrl.toEncoded().constData(), nullptr);
    if (item == nullptr)
        return;

    auto *job = new Job{ QPointer<SeekThumbnailer>(this), bucket, m_generation,
                         QFile::encodeName(path) };

    struct vlc_thumbnailer_arg arg{};
    /* `seek` is both a nested type and a member name, so name the type with decltype */
    using SeekArg = decltype(vlc_thumbnailer_arg::seek);
    arg.seek.type = SeekArg::VLC_THUMBNAILER_SEEK_TIME;
    arg.seek.time = VLC_TICK_FROM_SEC(bucket);
    arg.seek.speed = SeekArg::VLC_THUMBNAILER_SEEK_FAST;
    arg.hw_dec = false;

    struct vlc_thumbnailer_output output{};
    output.format = VLC_THUMBNAILER_FORMAT_JPEG;
    output.width = 320;
    output.height = 0;          /* keep the aspect ratio */
    output.crop = false;
    output.file_path = job->path.constData();
    output.creat_mode = 0644;

    static const struct vlc_thumbnailer_to_files_cbs cbs = { &SeekThumbnailer::onEnded };

    vlc_preparser_req *req = vlc_preparser_req_NewThumbnailToFiles(
                m_preparser, item, &arg, &output, 1, &cbs, job);
    input_item_Release(item);
    if (req == nullptr)
    {
        delete job;
        return;
    }

    m_inflight = bucket;
    if (vlc_preparser_Submit(m_preparser, req) != VLC_SUCCESS)
    {
        m_inflight = -1;
        vlc_preparser_req_Release(req);
        delete job;
    }
}

/* Preparser thread. Only forwards the result to the Qt thread. */
void SeekThumbnailer::onEnded(vlc_preparser_req *req, int status, const bool *results,
                              size_t count, void *data)
{
    Job *job = static_cast<Job *>(data);
    const bool ok = (status == VLC_SUCCESS && count > 0 && results != nullptr && results[0]);

    const QPointer<SeekThumbnailer> owner = job->owner;
    const int bucket = job->bucket;
    const int generation = job->generation;
    const QString path = QFile::decodeName(job->path);

    delete job;
    vlc_preparser_req_Release(req);

    QMetaObject::invokeMethod(qApp, [owner, bucket, generation, path, ok]() {
        if (owner && owner->m_generation == generation)
            owner->finished(bucket, path, ok);
    }, Qt::QueuedConnection);
}

void SeekThumbnailer::finished(int bucket, const QString &path, bool ok)
{
    if (m_inflight == bucket)
        m_inflight = -1;

    /* show it unless the user already moved on to another frame we have */
    if (ok && (m_wanted == bucket || m_wanted < 0 || !QFileInfo::exists(fileFor(m_wanted))))
        setSource(QUrl::fromLocalFile(path));

    /* the user moved while we were working: make the frame they are on now */
    if (m_wanted >= 0 && m_wanted != bucket)
        startNext();
}
