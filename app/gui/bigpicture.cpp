#include "bigpicture.h"

#include "settings/streamingpreferences.h"

#include <QCursor>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

#ifdef Q_OS_WIN32
#include <Windows.h>
#include <mmsystem.h>
#endif

#define SER_LASTHOST "bigpicture/lasthost"
#define SER_LASTAPP "bigpicture/lastapp/"
#define SER_LASTGAMEPAD "bigpicture/lastgamepad"

// Mouse movement smaller than this (in pixels, summed over both axes) since
// the last switch to controller input is treated as jitter.
#define MOUSE_JITTER_THRESHOLD 8

BigPicture* BigPicture::s_Instance = nullptr;

BigPicture::BigPicture(bool launchedDirectly, QObject* parent)
    : QObject(parent),
      m_LaunchedDirectly(launchedDirectly),
      m_Active(false),
      m_HadIntentionalInput(false),
      m_CursorHidden(false),
      m_InputMode(QStringLiteral("keyboard")),
      m_Glyphs(QStringLiteral("keyboard"))
{
    s_Instance = this;
    m_SinceLastAction.start();
    m_MouseAnchor = QCursor::pos();
    qApp->installEventFilter(this);

    // Clean up while the app is still fully alive: a sound playing from our
    // buffers or a hidden cursor must not outlive QGuiApplication.
    connect(qApp, &QCoreApplication::aboutToQuit, this, &BigPicture::shutdown);
}

BigPicture::~BigPicture()
{
    // Nothing here touches QGuiApplication: this object is destroyed as one of
    // its children, after the application itself has been torn down. The event
    // filter is removed automatically when this object is destroyed.
    stopSound();
    s_Instance = nullptr;
}

void BigPicture::stopSound()
{
#ifdef Q_OS_WIN32
    // Stop any sound still reading from m_Sounds before those buffers go away
    PlaySoundW(nullptr, nullptr, 0);
#endif
}

void BigPicture::shutdown()
{
    stopSound();
    setActive(false);   // shows the cursor again if Big Picture hid it
}

BigPicture* BigPicture::instance()
{
    return s_Instance;
}

bool BigPicture::isBigPictureExecutable(const QString& exePath)
{
    // Moonlight.BigPicture.exe -> "Moonlight.BigPicture"
    QString name = QFileInfo(exePath).completeBaseName();
    return name.compare(QStringLiteral("Moonlight.BigPicture"), Qt::CaseInsensitive) == 0 ||
           name.contains(QStringLiteral("BigPicture"), Qt::CaseInsensitive);
}

void BigPicture::setActive(bool active)
{
    if (m_Active == active) {
        return;
    }
    m_Active = active;

    // Anything that happened to the mouse while we weren't showing is stale
    m_MouseAnchor = QCursor::pos();

    applyCursor();
    emit activeChanged();
}

QString BigPicture::familyOf(SDL_GameController* gc)
{
    if (gc == nullptr) {
        return QStringLiteral("generic");
    }

    switch (SDL_GameControllerGetType(gc)) {
    case SDL_CONTROLLER_TYPE_XBOX360:
    case SDL_CONTROLLER_TYPE_XBOXONE:
        return QStringLiteral("xbox");
    case SDL_CONTROLLER_TYPE_PS3:
    case SDL_CONTROLLER_TYPE_PS4:
    case SDL_CONTROLLER_TYPE_PS5:
        return QStringLiteral("playstation");
    default:
        return QStringLiteral("generic");
    }
}

QString BigPicture::guidOf(SDL_GameController* gc)
{
    char buf[64] = {};
    if (gc != nullptr) {
        SDL_JoystickGetGUIDString(SDL_JoystickGetGUID(SDL_GameControllerGetJoystick(gc)),
                                  buf, sizeof(buf));
    }
    return QString::fromLatin1(buf);
}

void BigPicture::noteGamepadInput(SDL_GameController* gc)
{
    BigPicture* self = s_Instance;
    if (self == nullptr) {
        return;
    }

    self->m_HadIntentionalInput = true;

    // Remember which controller was used last, for the next startup
    QString guid = guidOf(gc);
    if (!guid.isEmpty()) {
        QSettings settings;
        if (settings.value(SER_LASTGAMEPAD).toString() != guid) {
            settings.setValue(SER_LASTGAMEPAD, guid);
        }
    }

    self->switchToGamepad(familyOf(gc));
}

void BigPicture::noteConnectedGamepads(const QList<SDL_GameController*>& gamepads)
{
    BigPicture* self = s_Instance;

    // Only decides the startup prompts. After the first real input, the most
    // recent input wins, and a controller sitting idle changes nothing.
    if (self == nullptr || self->m_HadIntentionalInput || gamepads.isEmpty()) {
        return;
    }

    SDL_GameController* chosen = gamepads.first();
    if (gamepads.size() > 1) {
        QString last = QSettings().value(SER_LASTGAMEPAD).toString();
        for (SDL_GameController* gc : gamepads) {
            if (!last.isEmpty() && guidOf(gc) == last) {
                chosen = gc;
                break;
            }
        }
    }

    self->switchToGamepad(familyOf(chosen));
}

void BigPicture::switchToGamepad(const QString& family)
{
    m_MouseAnchor = QCursor::pos();

    if (m_InputMode != QStringLiteral("gamepad") || m_Glyphs != family) {
        m_InputMode = QStringLiteral("gamepad");
        m_Glyphs = family;
        emit inputChanged();
    }

    applyCursor();
}

void BigPicture::switchToKeyboard()
{
    m_MouseAnchor = QCursor::pos();

    if (m_InputMode != QStringLiteral("keyboard")) {
        m_InputMode = QStringLiteral("keyboard");
        m_Glyphs = QStringLiteral("keyboard");
        emit inputChanged();
    }

    applyCursor();
}

void BigPicture::applyCursor()
{
    // Only the local Big Picture menus hide the cursor. While streaming (or in
    // the desktop UI) Moonlight's own cursor handling is left alone.
    bool hide = m_Active && m_InputMode == QStringLiteral("gamepad");

    if (hide && !m_CursorHidden) {
        QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor));
        m_CursorHidden = true;
    }
    else if (!hide && m_CursorHidden) {
        QGuiApplication::restoreOverrideCursor();
        m_CursorHidden = false;
    }
}

bool BigPicture::eventFilter(QObject* watched, QEvent* event)
{
    // Look at each event once, as it arrives at the window, and only at real
    // input from the OS. Keys synthesized from controller input and hover
    // updates from Qt Quick aren't spontaneous.
    if (!watched->isWindowType() || !event->spontaneous()) {
        return false;
    }

    switch (event->type()) {
    case QEvent::KeyPress:
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonDblClick:
    case QEvent::Wheel:
        switchToKeyboard();
        break;
    case QEvent::MouseMove:
    {
        QPoint pos = QCursor::pos();
        if (m_InputMode == QStringLiteral("keyboard")) {
            m_MouseAnchor = pos;
        }
        else if ((pos - m_MouseAnchor).manhattanLength() > MOUSE_JITTER_THRESHOLD) {
            switchToKeyboard();
        }
        break;
    }
    default:
        break;
    }

    return false;
}

QString BigPicture::lastHost() const
{
    return QSettings().value(SER_LASTHOST).toString();
}

void BigPicture::setLastHost(const QString& uuid)
{
    QSettings().setValue(SER_LASTHOST, uuid);
}

int BigPicture::lastApp(const QString& hostUuid) const
{
    return QSettings().value(QStringLiteral(SER_LASTAPP) + hostUuid, 0).toInt();
}

void BigPicture::setLastApp(const QString& hostUuid, int appId)
{
    if (!hostUuid.isEmpty()) {
        QSettings().setValue(QStringLiteral(SER_LASTAPP) + hostUuid, appId);
    }
}

const QByteArray* BigPicture::loadSound(const QString& name)
{
    auto it = m_Sounds.constFind(name);
    if (it != m_Sounds.constEnd()) {
        return &it.value();
    }

    QByteArray data;
    QStringList candidates;
    QString base = BigPictureFiles::folder();
    if (!base.isEmpty()) {
        candidates << QDir(base).filePath(QStringLiteral("sounds/%1.wav").arg(name));
    }
    candidates << QStringLiteral(":/res/sounds/%1.wav").arg(name);

    for (const QString& candidate : std::as_const(candidates)) {
        QFile file(candidate);
        if (file.open(QIODevice::ReadOnly)) {
            data = file.readAll();
            break;
        }
    }

    // Kept for the life of the app, since it must stay alive while it plays
    auto inserted = m_Sounds.insert(name, data);
    return &inserted.value();
}

void BigPicture::playSound(const QString& name)
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

    const QByteArray* data = loadSound(name);
    if (data == nullptr || data->isEmpty()) {
        return;
    }

#ifdef Q_OS_WIN32
    PlaySoundW(reinterpret_cast<LPCWSTR>(data->constData()), nullptr,
               SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
#endif
}

QString BigPictureFiles::folder()
{
    QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (docs.isEmpty()) {
        return QString();
    }

    QString path = QDir(docs).filePath(QStringLiteral("MoonlightBigPicture"));
    return QFileInfo(path).isDir() ? QDir::cleanPath(path) : QString();
}

void BigPictureFiles::install(QQmlEngine* engine)
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
    static BigPictureQmlInterceptor interceptor(QDir::cleanPath(gui));
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    engine->addUrlInterceptor(&interceptor);
#else
    engine->setUrlInterceptor(&interceptor);
#endif
}

BigPictureQmlInterceptor::BigPictureQmlInterceptor(const QString& guiFolder)
    : m_GuiFolder(guiFolder)
{
}

QUrl BigPictureQmlInterceptor::intercept(const QUrl& path, DataType type)
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

    // <folder>/X.qml that isn't there (e.g. StreamSegue.qml referenced from
    // a replaced file) -> back to the built-in qrc:/gui/X.qml
    if (path.isLocalFile()) {
        QString local = QDir::cleanPath(path.toLocalFile());
        if (local.startsWith(m_GuiFolder + QLatin1Char('/'), Qt::CaseInsensitive) && !QFileInfo::exists(local)) {
            return QUrl(QStringLiteral("qrc:/gui") + local.mid(m_GuiFolder.length()));
        }
    }

    return path;
}
