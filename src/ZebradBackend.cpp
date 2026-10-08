#include "ZebradBackend.h"

#include "logos_sdk.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>

#include <cmath>

namespace {
constexpr int kPollMs = 2000;
constexpr int kStartTimeoutMs = 30000;
constexpr int kStopTimeoutMs = 40000;  // Zebra gives its tasks 20 s to wind down
constexpr int kLogLines = 80;

QString toJson(const QVariantMap& m) {
    return QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(m)).toJson(QJsonDocument::Compact));
}
QString describe(const QString& e) { return e.isEmpty() ? QStringLiteral("unknown error") : e; }
QString describe(const logos::CallError& e) { return describe(QString::fromStdString(e.message)); }

// The module refuses a setting of the wrong type, and a JSON number arrives here as a double.
QVariantMap integral(QVariantMap m) {
    for (auto it = m.begin(); it != m.end(); ++it) {
        const double d = it->toDouble();
        if (it->typeId() == QMetaType::Double && std::floor(d) == d) *it = QVariant::fromValue<qint64>(qint64(d));
    }
    return m;
}

// Zebra's lines are "2026-10-08T03:01:52.132456Z  INFO span: crate::module: message";
// keep the time of day, the level and the message.
QString compactLog(const QString& raw) {
    static const QRegularExpression line(QStringLiteral(
        "^\\d{4}-\\d\\d-\\d\\dT(\\d\\d:\\d\\d:\\d\\d)\\S*\\s+(TRACE|DEBUG|INFO|WARN|ERROR)\\s+(.*)$"));
    static const QRegularExpression target(QStringLiteral("^.*?(?:[a-z_][a-z0-9_]*::)+[a-z_][a-z0-9_]*: "));
    QStringList out;
    for (const QString& l : raw.trimmed().split(u'\n')) {
        const auto m = line.match(l);
        if (!m.hasMatch()) { out << l; continue; }
        QString msg = m.captured(3);
        msg.remove(target);
        out << m.captured(1) + QStringLiteral("  ") + m.captured(2).leftJustified(5) + QStringLiteral("  ") + msg;
    }
    return out.join(u'\n');
}
}

ZebradBackend::ZebradBackend(QObject* parent) : ZebradBackendSimpleSource(parent) {
    setNetwork(QStringLiteral("testnet"));
    setNetworksJson(QStringLiteral("[\"mainnet\",\"testnet\"]"));
}

void ZebradBackend::onContextReady() {
    // The callback runs on the IPC read stack, so it only queues.
    modules().zebrad_module.onZebradStateChanged([this](QString payload) {
        QTimer::singleShot(0, this, [this, payload] {
            applyStatus(QJsonDocument::fromJson(payload.toUtf8()).object().toVariantMap());
        });
    });
    m_poll = new QTimer(this);
    m_poll->setInterval(kPollMs);
    connect(m_poll, &QTimer::timeout, this, [this] { poll(); });
    m_poll->start();
    probeRegtest();
    loadConfig();
    poll();
}

void ZebradBackend::applyStatus(QVariantMap st) {
    QString state = st.value("state").toString();
    if (state.isEmpty()) return;
    // A stop in flight can read "running" until Zebra has wound down.
    if (m_stopping && state == QLatin1String("running")) state = QStringLiteral("stopping");
    st.insert("state", state);
    setState(state);
    setStatusJson(toJson(st));
    const QString running = st.value("network").toString().toLower();
    if (!running.isEmpty() && state != QLatin1String("stopped") && running != network()) {
        setNetwork(running);  // show the node that is actually running
        setConfigJson({});
        loadConfig();
    }
}

void ZebradBackend::poll() {
    if (!isContextReady()) return;
    modules().zebrad_module.statusAsyncResult([this](logos::AsyncResult<QVariantMap> r) {
        if (!r.ok()) { setState(QStringLiteral("unavailable")); return; }
        applyStatus(r.value);
    });
    modules().zebrad_module.logTailAsyncResult(kLogLines, [this](logos::AsyncResult<QString> r) {
        if (r.ok()) setLogText(compactLog(r.value));
    });
}

// regtest exists only where the module's instance holds a regtest.json; then it has defaults.
void ZebradBackend::probeRegtest() {
    modules().zebrad_module.defaultConfigAsyncResult(QStringLiteral("regtest"), [this](logos::AsyncResult<QVariantMap> r) {
        if (r.ok() && !r.value.isEmpty()) setNetworksJson(QStringLiteral("[\"mainnet\",\"testnet\",\"regtest\"]"));
    });
}

void ZebradBackend::loadConfig() {
    if (!isContextReady()) return;
    const QString n = network();
    modules().zebrad_module.getConfigAsyncResult(n, [this, n](logos::AsyncResult<QVariantMap> r) {
        if (r.ok() && n == network()) setConfigJson(toJson(r.value));
    });
}

void ZebradBackend::selectNetwork(QString n) {
    if (n == network()) return;
    setNetwork(n);
    setConfigJson({});  // the form waits for this network's settings rather than show the last one's
    setLastError({});
    loadConfig();
}

void ZebradBackend::saveConfig(QString configJson) {
    if (!isContextReady()) return;
    const QString n = network();
    const QVariantMap cfg = integral(QJsonDocument::fromJson(configJson.toUtf8()).object().toVariantMap());
    modules().zebrad_module.configureAsyncResult(n, cfg, [this, n](logos::AsyncResult<LogosResult> r) {
        if (!r.ok()) { setLastError(describe(r.error)); return; }
        if (!r.value.success) { setLastError(describe(r.value.error.toString())); return; }
        setLastError({});
        if (n == network()) setConfigJson(toJson(r.value.value.toMap()));
    });
}

void ZebradBackend::start() {
    if (!isContextReady() || busy()) return;
    setBusy(true);
    setLastError({});
    modules().zebrad_module.startAsyncResult(network(), [this](logos::AsyncResult<LogosResult> r) {
        setBusy(false);
        if (!r.ok()) setLastError(describe(r.error));
        else if (!r.value.success) setLastError(describe(r.value.error.toString()));
        poll();
    }, Timeout(kStartTimeoutMs));
}

void ZebradBackend::stop() {
    if (!isContextReady() || busy()) return;
    setBusy(true);
    m_stopping = true;
    modules().zebrad_module.stopAsyncResult([this](logos::AsyncResult<LogosResult> r) {
        setBusy(false);
        m_stopping = false;
        if (!r.ok()) setLastError(describe(r.error));
        poll();
    }, Timeout(kStopTimeoutMs));
}

void ZebradBackend::refresh() {
    loadConfig();
    poll();
}
