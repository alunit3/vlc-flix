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

#ifndef SEEK_THUMBNAILER_HPP
#define SEEK_THUMBNAILER_HPP

#include <QObject>
#include <QString>
#include <QUrl>

Q_MOC_INCLUDE("maininterface/mainctx.hpp")
Q_MOC_INCLUDE("player/player_controller.hpp")

class MainCtx;
class PlayerController;

struct vlc_preparser_t;
struct vlc_preparser_req;

/**
 * flix: frame preview for the seek bar.
 *
 * QML calls request(seconds) while the mouse moves over the seek bar. A frame of the
 * current local video is written to a small JPEG in the cache folder (one per 10 s
 * bucket) by VLC's thumbnailer; `source` then points to the best frame available for the
 * last request, so the preview never flickers while a newer frame is being made.
 */
class SeekThumbnailer : public QObject
{
    Q_OBJECT

    Q_PROPERTY(MainCtx *ctx READ ctx WRITE setCtx NOTIFY ctxChanged FINAL)
    Q_PROPERTY(PlayerController *player READ player WRITE setPlayer NOTIFY playerChanged FINAL)

    /** the current media is a local video, so previews can be made */
    Q_PROPERTY(bool available READ available NOTIFY availableChanged FINAL)

    /** frame for the last request (or the previous frame while a new one is made) */
    Q_PROPERTY(QUrl source READ source NOTIFY sourceChanged FINAL)

public:
    explicit SeekThumbnailer(QObject *parent = nullptr);
    ~SeekThumbnailer() override;

    MainCtx *ctx() const { return m_ctx; }
    void setCtx(MainCtx *ctx);

    PlayerController *player() const { return m_player; }
    void setPlayer(PlayerController *player);

    bool available() const { return m_available; }
    QUrl source() const { return m_source; }

    /** ask for the frame at `seconds` into the media */
    Q_INVOKABLE void request(double seconds);

    /** forget the shown frame (when the mouse leaves the seek bar) */
    Q_INVOKABLE void clear();

signals:
    void ctxChanged();
    void playerChanged();
    void availableChanged();
    void sourceChanged();

private slots:
    void onInputChanged();

private:
    static constexpr int bucketSeconds = 10;

    struct Job;
    static void onEnded(vlc_preparser_req *req, int status, const bool *results,
                        size_t count, void *data);

    QString fileFor(int bucket) const;
    bool ensurePreparser();
    void updateAvailable();
    void startNext();
    void finished(int bucket, const QString &path, bool ok);
    void setSource(const QUrl &source);

    MainCtx *m_ctx = nullptr;
    PlayerController *m_player = nullptr;
    vlc_preparser_t *m_preparser = nullptr;

    bool m_available = false;
    QUrl m_source;

    QString m_cacheDir;
    QString m_mediaKey;          // identifies the current media in file names
    QUrl m_mediaUrl;

    int m_wanted = -1;           // bucket the user is hovering, -1 if none
    int m_inflight = -1;         // bucket being generated, -1 if none
    int m_generation = 0;        // changes with the media, to drop late results
};

#endif // SEEK_THUMBNAILER_HPP
