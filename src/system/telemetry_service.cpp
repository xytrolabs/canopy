#include "system/telemetry_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "net/http_client.h"
#include "wayland/wayland_connection.h"

namespace {

  constexpr Logger kLog("telemetry");

} // namespace

void TelemetryService::maybeSend(
    const ConfigService& config, HttpClient& httpClient, const WaylandConnection& wayland
) {
  if (m_sent) {
    return;
  }
  m_sent = true;

  // The ping endpoint no longer exists upstream (https://api.noctalia.dev/ping returns 404 at
  // every path tried), so this only ever posted an anonymous payload into a 404 and logged
  // "ping failed" at debug level. Canopy does not phone home.
  (void)config;
  (void)httpClient;
  (void)wayland;
  kLog.debug("telemetry ping disabled; Canopy sends nothing");
}
