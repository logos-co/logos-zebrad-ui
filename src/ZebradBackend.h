#pragma once

#include "logos_ui_plugin_context.h"
#include "rep_ZebradBackend_source.h"

#include <QTimer>
#include <QVariantMap>

// Every zebrad_module call is made here; the QML renders. The event carries state changes
// at once; the poll carries height and peers, which move without one.
class ZebradBackend : public ZebradBackendSimpleSource, public LogosUiPluginContext {
    Q_OBJECT
public:
    explicit ZebradBackend(QObject* parent = nullptr);

    void selectNetwork(QString network) override;
    void saveConfig(QString configJson) override;
    void start() override;
    void stop() override;
    void refresh() override;

protected:
    void onContextReady() override;

private:
    void poll();
    void loadConfig();
    void applyStatus(QVariantMap st);
    void probeRegtest();

    QTimer* m_poll = nullptr;
    bool m_stopping = false;
};
