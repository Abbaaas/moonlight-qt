#pragma once

#include <QObject>
#include <QHash>
#include <QByteArray>
#include <QElapsedTimer>
#include <QQmlAbstractUrlInterceptor>

// Helpers for TV mode:
//
// - TvSound plays short navigation sounds (move, select, back, toggle, error).
//   Sounds come from res/sounds in the app, or from the sounds folder of the
//   TV mode files folder when that exists.
//
// - TvFiles lets TV mode's screens and sounds be replaced without rebuilding:
//   if Documents/MoonlightTV/gui exists, any qrc:/gui/<name>.qml that also
//   exists there is loaded from that folder instead. Restart Moonlight to
//   pick up changes.

class TvFiles
{
public:
    // Folder holding replacement files (Documents/MoonlightTV), or an empty
    // string when it doesn't exist.
    static QString folder();

    // Installs the URL interceptor on the engine when the folder exists.
    static void install(class QQmlEngine* engine);
};

class TvQmlInterceptor : public QQmlAbstractUrlInterceptor
{
public:
    explicit TvQmlInterceptor(const QString& guiFolder);
    QUrl intercept(const QUrl& path, DataType type) override;

private:
    QString m_GuiFolder;
};

class TvSound : public QObject
{
    Q_OBJECT

public:
    explicit TvSound(QObject* parent = nullptr);

    // name: "move", "select", "back", "toggle" or "error"
    Q_INVOKABLE void play(const QString& name);

private:
    const QByteArray* load(const QString& name);

    QHash<QString, QByteArray> m_Cache;
    QElapsedTimer m_SinceLastAction;
};
