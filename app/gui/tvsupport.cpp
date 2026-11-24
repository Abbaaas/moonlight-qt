#include "tvsupport.h"

#include "settings/streamingpreferences.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QQmlEngine>
#include <QStandardPaths>
#include <QUrl>

#ifdef Q_OS_WIN
#include <windows.h>
#include <mmsystem.h>
#endif

QString TvFiles::folder()
{
    QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (docs.isEmpty()) {
        return QString();
    }

    QString path = QDir(docs).filePath(QStringLiteral("MoonlightTV"));
    return QFileInfo(path).isDir() ? QDir::cleanPath(path) : QString();
}

void TvFiles::install(QQmlEngine* engine)
{
    QString base = folder();
    if (base.isEmpty()) {
        return;
    }

    QString gui = QDir(base).filePath(QStringLiteral("gui"));
    if (!QFileInfo(gui).isDir()) {
        return;
    }

    // Lives as long as the app
    static TvQmlInterceptor interceptor(QDir::cleanPath(gui));
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    engine->addUrlInterceptor(&interceptor);
#else
    engine->setUrlInterceptor(&interceptor);
#endif
}

TvQmlInterceptor::TvQmlInterceptor(const QString& guiFolder)
    : m_GuiFolder(guiFolder)
{
}

QUrl TvQmlInterceptor::intercept(const QUrl& path, DataType type)
{
    if (type != QmlFile && type != JavaScriptFile && type != UrlString) {
        return path;
    }

    // qrc:/gui/X.qml -> <folder>/X.qml when the folder has a copy
    if (path.scheme() == QStringLiteral("qrc") && path.path().startsWith(QStringLiteral("/gui/"))) {
        QString local = m_GuiFolder + path.path().mid(4);
        if (QFileInfo::exists(local)) {
            return QUrl::fromLocalFile(local);
        }
        return path;
    }

    // <folder>/X.qml that isn't there (e.g. StreamSegue.qml, referenced from
    // a replaced file) -> back to the built-in qrc:/gui/X.qml
    if (path.isLocalFile()) {
        QString local = QDir::cleanPath(path.toLocalFile());
        if (local.startsWith(m_GuiFolder + QLatin1Char('/'), Qt::CaseInsensitive) && !QFileInfo::exists(local)) {
            return QUrl(QStringLiteral("qrc:/gui") + local.mid(m_GuiFolder.length()));
        }
    }

    return path;
}

TvSound::TvSound(QObject* parent)
    : QObject(parent)
{
    m_SinceLastAction.start();
}

const QByteArray* TvSound::load(const QString& name)
{
    auto it = m_Cache.constFind(name);
    if (it != m_Cache.constEnd()) {
        return &it.value();
    }

    QByteArray data;
    QString base = TvFiles::folder();
    QStringList candidates;
    if (!base.isEmpty()) {
        candidates << QDir(base).filePath(QStringLiteral("sounds/%1.wav").arg(name));
    }
    candidates << QStringLiteral(":/res/sounds/%1.wav").arg(name);

    for (const QString& candidate : candidates) {
        QFile file(candidate);
        if (file.open(QIODevice::ReadOnly)) {
            data = file.readAll();
            break;
        }
    }

    // The data must stay alive while it plays, so it's kept in the cache
    // for the life of the app.
    auto inserted = m_Cache.insert(name, data);
    return &inserted.value();
}

void TvSound::play(const QString& name)
{
    if (!StreamingPreferences::get()->tvSounds) {
        return;
    }

    // Don't let the "move" tick from focus landing on a new screen cut off
    // the sound of the button press that opened it.
    bool isMove = name == QStringLiteral("move");
    if (isMove && m_SinceLastAction.elapsed() < 180) {
        return;
    }
    if (!isMove) {
        m_SinceLastAction.restart();
    }

    const QByteArray* data = load(name);
    if (data == nullptr || data->isEmpty()) {
        return;
    }

#ifdef Q_OS_WIN
    PlaySoundW(reinterpret_cast<LPCWSTR>(data->constData()), nullptr,
               SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
#endif
}
